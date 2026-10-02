-- Recoverable PDF/sidecar transactions for imported annotations only.
-- Staging files and backups are retained on error. No writes go to the live
-- MuPDF handle: callers edit a separate snapshot and reopen after commit.
local dump = require("dump")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local sha256 = require("ffi/sha2").sha256
local util = require("util")

local Transaction = {}
local serial = 0

function Transaction.id()
    serial = serial + 1
    return tostring(os.time()) .. "-" .. tostring(serial) .. "-" .. tostring(math.random(100000, 999999))
end

function Transaction.hash(path)
    if not lfs.attributes(path) then return "absent" end
    local file = assert(io.open(path, "rb"))
    local update = sha256()
    local expected = assert(file:seek("end"))
    assert(file:seek("set"))
    local read = 0
    while true do
        local bytes, err = file:read(65536)
        if not bytes then
            assert(not err, err)
            break
        end
        read = read + #bytes
        update(bytes)
    end
    assert(file:close())
    assert(read == expected, "Short read: " .. path)
    return update()
end

function Transaction.write(path, bytes)
    local file = assert(io.open(path, "wb"))
    local ok, err = pcall(function()
        assert(file:write(bytes))
        assert(file:flush())
        assert(ffiUtil.fsyncOpenedFile(file, true))
    end)
    local closed, close_err = file:close()
    assert(ok, err)
    assert(closed, close_err)
    assert(Transaction.hash(path) == sha256(bytes), "Staged file verification failed")
end

function Transaction.syncFile(path)
    local file = assert(io.open(path, "rb"))
    local ok, err = ffiUtil.fsyncOpenedFile(file, true)
    local closed, close_err = file:close()
    assert(ok, err)
    assert(closed, close_err)
    assert(ffiUtil.fsyncDirectory(path))
end

function Transaction.copy(source, destination)
    local input = assert(io.open(source, "rb"))
    local output = assert(io.open(destination, "wb"))
    local ok, err = pcall(function()
        while true do
            local bytes, read_err = input:read(65536)
            assert(not read_err, read_err)
            if not bytes then break end
            assert(output:write(bytes))
        end
        assert(output:flush())
        assert(ffiUtil.fsyncOpenedFile(output, true))
    end)
    local in_ok, in_err = input:close()
    local out_ok, out_err = output:close()
    assert(ok, err)
    assert(in_ok, in_err)
    assert(out_ok, out_err)
    assert(Transaction.hash(source) == Transaction.hash(destination), "Backup verification failed")
    assert(ffiUtil.fsyncDirectory(destination))
end

local function rename(source, destination)
    assert(os.rename(source, destination))
    assert(ffiUtil.fsyncDirectory(destination))
end

function Transaction.readTable(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, {})
    local data = chunk()
    assert(type(data) == "table", "Invalid staged metadata")
    return data
end

function Transaction.writeTable(path, data)
    local bytes = "-- KOReaderX staged annotation transaction\nreturn " .. dump(data, nil, true) .. "\n"
    Transaction.write(path, bytes)
    assert(dump(Transaction.readTable(path), nil, true) == dump(data, nil, true), "Metadata roundtrip failed")
end

-- Keep the active location; follow DocSettings' preferred location for a new
-- sidecar. Never purge an alternate copy during a transaction.
function Transaction.metadataPath(settings, readonly)
    if settings.source_candidate then
        return (settings.source_candidate:gsub("%.old$", ""))
    end
    local location = G_reader_settings:readSetting("document_metadata_folder", "doc")
    local directory
    if location == "hash" then
        directory = settings.hash_sidecar_dir or settings:getSidecarDir(settings.data.doc_path, "hash")
    elseif location == "dir" then
        directory = settings.dir_sidecar_dir
    else
        directory = settings.doc_sidecar_dir
    end
    assert(directory and settings.sidecar_filename, "Missing document sidecar location")
    if not readonly then
        util.makePath(directory)
        assert(lfs.attributes(directory, "mode") == "directory", "Cannot create metadata directory")
    end
    return directory .. "/" .. settings.sidecar_filename
end

-- Keep the hash of the sidecar actually loaded, not merely the hash found at
-- edit time. Otherwise a sync tool's earlier edit could be silently replaced.
function Transaction.observeMetadata(settings, source, loaded_hash)
    local target = Transaction.metadataPath(settings, true)
    source = source or target
    local current = Transaction.hash(source)
    assert(not loaded_hash or current == loaded_hash, "Metadata changed while opening the book")
    settings.koreaderx_metadata_baseline = { [source] = current }
    if source ~= target then settings.koreaderx_metadata_baseline[target] = Transaction.hash(target) end
end

function Transaction.assertMetadataUnchanged(settings)
    for path, expected in pairs(settings.koreaderx_metadata_baseline or {}) do
        local ok, current = pcall(Transaction.hash, path)
        if not ok or current ~= expected then
            settings.koreaderx_transaction_blocked = true
            error("Metadata changed outside KOReader. Preserve both versions and close/reopen the book before editing: " .. path)
        end
    end
end

function Transaction.stageMetadata(settings, data, id, destination)
    assert(not settings.koreaderx_transaction_blocked, "PDF transaction recovery is required before editing metadata")
    Transaction.assertMetadataUnchanged(settings)
    local source = Transaction.metadataPath(settings)
    destination = destination or source
    local source_hash = Transaction.hash(source)
    if source ~= destination and source_hash ~= "absent" then
        Transaction.copy(source, source .. ".koreaderx-" .. id .. ".backup")
    end
    local staged = destination .. ".koreaderx-" .. id .. ".new"
    local before = Transaction.hash(destination)
    local backup = destination .. ".koreaderx-" .. id .. ".backup"
    if before ~= "absent" then Transaction.copy(destination, backup) end
    Transaction.writeTable(staged, data)
    return {
        path = destination, staged = staged, backup = backup,
        before = before, after = Transaction.hash(staged),
        source = source ~= destination and source or nil,
        source_hash = source ~= destination and source_hash or nil,
    }
end

function Transaction.commitMetadata(settings, data)
    local staged = Transaction.stageMetadata(settings, data, Transaction.id())
    assert(Transaction.hash(staged.path) == staged.before, "Metadata changed outside KOReader")
    rename(staged.staged, staged.path)
    assert(Transaction.hash(staged.path) == staged.after, "Metadata commit verification failed")
    settings.source_candidate = staged.path
    settings.data = data
    Transaction.observeMetadata(settings, staged.path, staged.after)
end

function Transaction.journalPath(pdf_path)
    return pdf_path .. ".koreaderx-annotation-transaction.lua"
end

-- Returns only after disk holds a consistent pair. Unknown hashes are an
-- external-edit conflict: preserve every artifact and require reconciliation.
function Transaction.recover(pdf_path)
    local path = Transaction.journalPath(pdf_path)
    if not lfs.attributes(path) then return false end
    local journal = Transaction.readTable(path)
    assert(journal.version == 1 and journal.pdf.path == pdf_path, "Invalid PDF transaction journal")
    local pdf_state = Transaction.hash(pdf_path)
    local metadata = journal.metadata
    local metadata_state = Transaction.hash(metadata.path)
    assert(not metadata.source or Transaction.hash(metadata.source) == metadata.source_hash,
        "Original sidecar changed during PDF transaction; reconciliation required")
    if pdf_state == journal.pdf.after and metadata_state == metadata.before then
        assert(Transaction.hash(metadata.staged) == metadata.after, "Missing staged metadata; recovery required")
        rename(metadata.staged, metadata.path)
        metadata_state = Transaction.hash(metadata.path)
    end
    local committed = pdf_state == journal.pdf.after and metadata_state == metadata.after
    local unchanged = pdf_state == journal.pdf.before and metadata_state == metadata.before
    assert(committed or unchanged, "PDF/metadata recovery conflict; preserve transaction backups")
    rename(path, path .. "." .. journal.id .. (committed and ".committed" or ".aborted"))
    return committed
end

function Transaction.commitPair(pdf_path, staged_pdf, metadata, id, expected_pdf_hash)
    local path = Transaction.journalPath(pdf_path)
    assert(not lfs.attributes(path), "An unfinished PDF transaction requires recovery")
    assert(Transaction.hash(pdf_path) == expected_pdf_hash, "PDF changed outside KOReader")
    assert(Transaction.hash(metadata.path) == metadata.before, "Metadata changed outside KOReader")
    assert(not metadata.source or Transaction.hash(metadata.source) == metadata.source_hash, "Original sidecar changed outside KOReader")
    Transaction.syncFile(staged_pdf)
    local backup = pdf_path .. ".koreaderx-" .. id .. ".backup"
    Transaction.copy(pdf_path, backup)
    local journal = {
        version = 1, id = id,
        pdf = { path = pdf_path, staged = staged_pdf, backup = backup,
            before = expected_pdf_hash, after = Transaction.hash(staged_pdf) },
        metadata = metadata,
    }
    Transaction.writeTable(path .. ".new", journal)
    rename(path .. ".new", path)
    -- Recheck after durable preparation. No operation may overwrite an edit
    -- made by another application while the candidate was being prepared.
    assert(Transaction.hash(pdf_path) == expected_pdf_hash, "PDF changed before commit")
    assert(Transaction.hash(metadata.path) == metadata.before, "Metadata changed before commit")
    assert(not metadata.source or Transaction.hash(metadata.source) == metadata.source_hash, "Original sidecar changed before commit")
    rename(staged_pdf, pdf_path)
    rename(metadata.staged, metadata.path)
    assert(Transaction.recover(pdf_path), "PDF transaction did not commit")
end

return Transaction
