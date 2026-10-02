describe("KOReaderX highlight navigation", function()
    local ReaderBookmark
    setup(function()
        require("commonrequire")
        ReaderBookmark = require("apps/reader/modules/readerbookmark")
    end)
    for _, pdf in ipairs({ true, false }) do
        it("skips page bookmarks and the current highlight page for " .. (pdf and "PDF" or "EPUB"), function()
            local events, history = {}, 0
            local current = 5
            local function point(page) return pdf and page or "xp:" .. page end
            local bookmark = setmetatable({
                document = {
                    getXPointer = function() return point(current) end,
                    getPageFromXPointer = function(_, xp) return tonumber(xp:match("xp:(%d+)")) end,
                },
                view = { state = { page = current } },
                ui = {
                    paging = pdf or nil,
                    annotation = { annotations = {
                        { page = point(9), drawer = "lighten" }, -- deliberately not sorted
                        { page = point(3) },
                        { page = point(5), drawer = "lighten" },
                        { page = point(2), drawer = "lighten", note = "note" },
                        { page = point(5), drawer = "underscore" },
                    } },
                    link = { addCurrentLocationToStack = function() history = history + 1 end },
                    handleEvent = function(_, ev) events[#events + 1] = ev end,
                },
            }, { __index = ReaderBookmark })
            bookmark:onGotoNextHighlightPageFromPage()
            assert.are.equal(pdf and "GotoPage" or "GotoXPointer", events[1].handler:sub(3))
            assert.are.equal(point(9), events[1].args[1])
            assert.are.equal(1, history)
            bookmark:onGotoPreviousHighlightPageFromPage(false)
            assert.are.equal(point(2), events[2].args[1])
            assert.are.equal(1, history)
            current, bookmark.view.state.page = 9, 9
            bookmark:onGotoNextHighlightPageFromPage()
            assert.are.equal(2, #events)
            assert.are.equal(1, history)
        end)
    end
end)
