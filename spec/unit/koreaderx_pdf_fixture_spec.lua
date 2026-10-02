describe("KOReaderX supplied PDF regression fixture", function()
    it("keeps the extracurriculars native selection within one line", function()
        local fixture = os.getenv("KOREADERX_PDF_FIXTURE")
        if not fixture then pending("Set KOREADERX_PDF_FIXTURE to the supplied, copied PDF") end
        require("commonrequire")
        local DocumentRegistry = require("document/documentregistry")
        local doc = DocumentRegistry:openDocument(fixture)
        doc.configurable.text_wrap = 0
        local page = doc._document:openPage(1)
        local lines = page:getPageText()
        page:close()
        local word
        for _, line in ipairs(lines) do
            for _, candidate in ipairs(line) do
                if candidate.word:find("extracurriculars", 1, true) then
                    assert.is_nil(word)
                    word = candidate
                end
            end
        end
        assert.is_truthy(word)
        local pos = { page = 1, x = (word.x0 + word.x1) / 2, y = (word.y0 + word.y1) / 2 }
        local selected = doc:getWordFromPosition(pos)
        local span = doc:getTextFromPositions(pos, pos)
        assert.are.equal(word.word, selected.word)
        assert.are.equal(word.word, span.text)
        assert.are.equal(1, #span.pboxes)
        assert.is_true(selected.pbox.h < 2 * (word.y1 - word.y0))
        assert.is_true(span.pboxes[1].h < 2 * (word.y1 - word.y0))
        doc:close()
    end)
end)
