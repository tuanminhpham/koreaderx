-- Real-engine regression: this fixture is supplied by the project owner and
-- deliberately remains outside Git. See the S10 evidence for its SHA256.
describe("KOReaderX supplied PDF reflow geometry", function()
    local Registry, Screen, Canvas, Transaction, ffiUtil, util
    local directory, filename, doc, native_item, previous_screen
    setup(function()
        require("commonrequire")
        Registry = require("document/documentregistry")
        Screen = require("device").screen
        Canvas = require("document/canvascontext")
        Transaction = require("document/pdfannotationtransaction")
        ffiUtil = require("ffi/util")
        util = require("util")
    end)
    before_each(function()
        local fixture = os.getenv("KOREADERX_PDF_FIXTURE")
        if not fixture then pending("Set KOREADERX_PDF_FIXTURE to the supplied one-page PDF") end
        directory = os.tmpname(); os.remove(directory); util.makePath(directory)
        filename = directory .. "/reflow.pdf"
        Transaction.copy(fixture, filename)
        previous_screen = { w = Screen:getWidth(), h = Screen:getHeight(), dpi = Screen:getDPI(),
            color = Canvas.is_color_rendering_enabled }
        Screen:_newBB(2400, 3200); Screen:setDPI(300)
        Canvas:setColorRenderingEnabled(true)
        doc = Registry:openDocument(filename)
        doc.configurable.text_wrap = 0
        local page = doc._document:openPage(1)
        local lines = page:getPageText()
        page:close()
        local word
        for _, line in ipairs(lines) do
            for _, candidate in ipairs(line) do
                if candidate.word == "extracurriculars." then word = candidate end
            end
        end
        assert.truthy(word)
        local pos = {page = 1, x = (word.x0 + word.x1)/2, y = (word.y0 + word.y1)/2}
        native_item = doc:getTextFromPositions(pos, pos)
        native_item.color, native_item.drawer = "green", "lighten"
    end)
    after_each(function()
        if doc then doc:close(); doc = nil end
        if directory then assert(ffiUtil.purgeDir(directory)); directory = nil end
        if previous_screen then
            Screen:_newBB(previous_screen.w, previous_screen.h)
            Screen:setDPI(previous_screen.dpi)
            Canvas:setColorRenderingEnabled(previous_screen.color)
            previous_screen = nil
        end
    end)
    local function reflow(cropped)
        doc.configurable.text_wrap = 1
        doc.configurable.trim_page = cropped and 0 or 3
        doc.configurable.font_size = 1
        if cropped then doc.bbox[1] = {x0 = 5, y0 = 5, x1 = 330, y1 = 505} end
        return doc:getPageBoxesFromPositions(1, native_item.pos0, native_item.pos1)
    end
    it("keeps clean-page word geometry and leaves native pboxes unchanged", function()
        local saved = util.tableDeepCopy(native_item.pboxes)
        for _, cropped in ipairs({false, true}) do
            local boxes = reflow(cropped)
            assert.equals(1, #boxes)
            assert.is_true(boxes[1].w > 100 and boxes[1].w < 1200)
            assert.is_true(boxes[1].h > 20 and boxes[1].h < 200)
        end
        doc.configurable.text_wrap = 0
        assert.same(saved, doc:getPageBoxesFromPositions(1, native_item.pos0, native_item.pos1))
        assert.same(saved, native_item.pboxes)
    end)
    it("keeps a persisted colored word within its rendered bounds instead of its whole line", function()
        doc:saveHighlight(1, native_item)
        doc:close(); doc = Registry:openDocument(filename)
        local boxes = reflow(true)
        assert.equals(1, #boxes)
        local box = boxes[1]
        assert.is_true(box.w < 1200) -- old center/rectmap lookup yields 2339 px
        local kc = doc.koptinterface:getCachedContext(doc, 1)
        local bb = kc:dstToBlitBuffer()
        local left, right, count = bb.w, -1, 0
        for y = math.max(0, math.floor(box.y) - 5), math.min(bb.h - 1, math.ceil(box.y + box.h) + 5) do
            for x = 0, bb.w - 1 do
                local c = bb:getPixelP(x, y)[0]:getColorRGB24()
                if c.g > 120 and c.g > c.r + 30 and c.g > c.b + 20 then
                    left, right, count = math.min(left, x), math.max(right, x), count + 1
                end
            end
        end
        bb:free()
        assert.is_true(count > 100)
        -- MuPDF's curved highlight appearance extends slightly beyond its quad.
        assert.is_true(math.abs(box.x - left) < 40)
        assert.is_true(math.abs(box.x + box.w - right) < 40)
        doc.configurable.text_wrap = 0
        assert.same(native_item.pboxes, doc:getPageBoxesFromPositions(1, native_item.pos0, native_item.pos1))
    end)
    it("keeps multiline selection as bounded reflow fragments", function()
        local text = doc:getPageTextBoxes(1)
        local first, last = text[13][1], text[14][#text[14]]
        local pos0 = {page = 1, x = (first.x0 + first.x1)/2, y = (first.y0 + first.y1)/2}
        local pos1 = {page = 1, x = (last.x0 + last.x1)/2, y = (last.y0 + last.y1)/2}
        local native = doc:getTextFromPositions(pos0, pos1)
        assert.equals(2, #native.pboxes)
        reflow(true)
        local boxes = doc:getPageBoxesFromPositions(1, pos0, pos1)
        assert.is_true(#boxes > 1)
        for _, box in ipairs(boxes) do
            assert.is_true(box.w > 0 and box.w <= 2400)
            assert.is_true(box.h > 0 and box.h < 200)
        end
        doc.configurable.text_wrap = 0
        assert.same(native.pboxes, doc:getPageBoxesFromPositions(1, pos0, pos1))
    end)
end)
