-- PDF source identities are per document. Never serialize a MuPDF pointer.
local dump = require("dump")
local sha256 = require("ffi/sha2").sha256
local util = require("util")

local PdfAnnotations = {}

PdfAnnotations.drawers = { [8] = "lighten", [9] = "underscore", [10] = "underscore", [11] = "strikeout" }
PdfAnnotations.types = { lighten = 8, underscore = 9, strikeout = 11 }

function PdfAnnotations.fingerprint(value)
    return sha256(dump(value, nil, true))
end

function PdfAnnotations.part(page, annotation)
    assert(annotation.source and annotation.raw, "PDF source metadata is unavailable")
    return {
        page = page,
        num = annotation.source.num,
        gen = annotation.source.gen,
        raw = util.tableDeepCopy(annotation.raw),
    }
end

function PdfAnnotations.sameSource(a, b)
    return a.page == b.page and a.num == b.num and a.gen == b.gen
        and PdfAnnotations.fingerprint(a.raw) == PdfAnnotations.fingerprint(b.raw)
end

function PdfAnnotations.nearestColor(rgb, palette)
    if not rgb then return "yellow" end
    local best, distance
    for name, hex in pairs(palette) do
        local r, g, b = hex:match("#(..)(..)(..)")
        local d = (rgb[1] * 255 - tonumber(r, 16)) ^ 2
            + (rgb[2] * 255 - tonumber(g, 16)) ^ 2
            + (rgb[3] * 255 - tonumber(b, 16)) ^ 2
        if not distance or d < distance or (d == distance and name < best) then
            best, distance = name, d
        end
    end
    return best
end

function PdfAnnotations.validBoxes(boxes)
    if type(boxes) ~= "table" or #boxes == 0 then return false end
    for _, box in ipairs(boxes) do
        for _, key in ipairs({"x", "y", "w", "h"}) do
            local n = box[key]
            if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then return false end
        end
        if box.w <= 0 or box.h <= 0 then return false end
    end
    return true
end

-- Geometry can identify an unresolved legacy collision, never ownership.
-- Fresh local-only highlights carry an explicit empty owned-parts list.
function PdfAnnotations.legacyGeometryMatches(item, page, annotation)
    if not item.drawer or item.koreaderx_pdf_source or item.koreaderx_pdf_owned then return false end
    local boxes
    if item.ext then boxes = item.ext[page] and item.ext[page].pboxes
    elseif (item.pos0 and item.pos0.page or item.page) == page then boxes = item.pboxes end
    if not PdfAnnotations.validBoxes(boxes) or not annotation.raw then return false end
    local quads = PdfAnnotations.quads(boxes)
    local other = annotation.raw.quads
    if not other or #quads ~= #other then return false end
    for i, quad in ipairs(quads) do
        for j, value in ipairs(quad) do
            if not other[i][j] or math.abs(value - other[i][j]) > 0.0001 then return false end
        end
    end
    return true
end

-- Match the complete source snapshot, including multiplicity for direct objects.
-- Geometry alone is deliberately insufficient: two authors may annotate the same word.
function PdfAnnotations.import(annotations, existing, tombstones, build_item)
    local candidate = util.tableDeepCopy(existing)
    local seen, anonymous, old_identity = {}, {}, {}
    local snapshots, input_ids, input_counts, missing_owned_snapshots = {}, {}, {}, {}
    for page, entries in pairs(annotations or {}) do
        for _, entry in ipairs(entries) do
            if entry.source and entry.raw then
                input_ids[page .. ":" .. entry.source.num .. ":" .. entry.source.gen] = true
                local key = page .. ":" .. PdfAnnotations.fingerprint(entry.raw)
                input_counts[key] = (input_counts[key] or 0) + 1
            end
        end
    end
    local function remember(part, owned)
        local raw = PdfAnnotations.fingerprint(part.raw)
        local key = part.page .. ":" .. part.num .. ":" .. part.gen .. ":" .. raw
        if part.num == 0 then
            anonymous[key] = (anonymous[key] or 0) + 1
        else
            seen[key] = true
            old_identity[part.page .. ":" .. part.num .. ":" .. part.gen] = raw
            local snapshot = part.page .. ":" .. raw
            if owned then
                if not input_ids[part.page .. ":" .. part.num .. ":" .. part.gen] then missing_owned_snapshots[snapshot] = true end
            else
                snapshots[snapshot] = snapshots[snapshot] or {}
                table.insert(snapshots[snapshot], part)
            end
        end
    end
    for _, item in ipairs(candidate) do
        if item.koreaderx_pdf_source then
            for _, part in ipairs(item.koreaderx_pdf_source.parts) do remember(part) end
        end
        local owned = item.koreaderx_pdf_owned
        if owned then
            assert(owned.version == 1 and type(owned.parts) == "table", "Invalid owned PDF provenance")
            for _, part in ipairs(owned.parts) do remember(part, true) end
            -- A manual settings flush may precede ordinary write-on-close.
            if owned.pending then
                for _, part in ipairs(owned.pending.parts) do remember(part, true) end
            end
        end
    end
    for _, part in ipairs(tombstones or {}) do remember(part, part.koreaderx_owned) end
    local added, skipped, invalid, conflicts = {}, 0, 0, 0
    local pages = {}
    for page in pairs(annotations or {}) do pages[#pages + 1] = page end
    table.sort(pages)
    for _, page in ipairs(pages) do
        for _, annotation in ipairs(annotations[page]) do
            if not PdfAnnotations.drawers[annotation.type] or not PdfAnnotations.validBoxes(annotation.boxes) then
                invalid = invalid + 1
            else
                local part = PdfAnnotations.part(page, annotation)
                local raw = PdfAnnotations.fingerprint(part.raw)
                local id = page .. ":" .. part.num .. ":" .. part.gen
                local key = id .. ":" .. raw
                local legacy_conflict = false
                for _, item in ipairs(candidate) do
                    if PdfAnnotations.legacyGeometryMatches(item, page, annotation) then
                        legacy_conflict = true
                        break
                    end
                end
                if seen[key] or (anonymous[key] or 0) > 0 then
                    skipped = skipped + 1
                    if part.num == 0 then anonymous[key] = anonymous[key] - 1 end
                elseif snapshots[page .. ":" .. raw] and part.num > 0
                    and not input_ids[snapshots[page .. ":" .. raw][1].page .. ":"
                        .. snapshots[page .. ":" .. raw][1].num .. ":" .. snapshots[page .. ":" .. raw][1].gen] then
                    local matches = snapshots[page .. ":" .. raw]
                    local old = matches[1]
                    if #matches == 1 and input_counts[page .. ":" .. raw] == 1
                        and not input_ids[old.page .. ":" .. old.num .. ":" .. old.gen] then
                        -- A rewrite changed xrefs, but the complete source
                        -- snapshot uniquely identifies the same annotation.
                        old.num, old.gen = part.num, part.gen
                        seen[key] = true
                        skipped = skipped + 1
                    else
                        conflicts = conflicts + 1
                    end
                elseif part.num > 0 and old_identity[id] and old_identity[id] ~= raw then
                    -- Preserve local text/note/overrides; ask for reconciliation, never overwrite.
                    conflicts = conflicts + 1
                elseif legacy_conflict or missing_owned_snapshots[page .. ":" .. raw] then
                    -- Unknown legacy provenance is not proof that this is ours.
                    -- Report a conflict instead of duplicating or dropping a source.
                    conflicts = conflicts + 1
                else
                    local item = build_item(page, annotation)
                    item.koreaderx_pdf_source = { version = 1, parts = { part } }
                    candidate[#candidate + 1] = item
                    added[#added + 1] = item
                    if part.num > 0 then seen[key], old_identity[id] = true, raw end
                end
            end
        end
    end
    return candidate, added, skipped, invalid, conflicts
end

function PdfAnnotations.quads(boxes)
    assert(PdfAnnotations.validBoxes(boxes), "Invalid highlight geometry")
    local quads = {}
    for _, box in ipairs(boxes) do
        quads[#quads + 1] = {
            box.x, box.y, box.x + box.w - 1, box.y,
            box.x, box.y + box.h - 1, box.x + box.w - 1, box.y + box.h - 1,
        }
    end
    return quads
end

return PdfAnnotations
