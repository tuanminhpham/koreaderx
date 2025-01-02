# KOReaderX
#### a document viewer primarily aimed at e-ink readers.

# Introducing New Koreader Features: “Import Highlights from a PDF File” and “Highlight Navigation”

[![AGPL Licence][badge-license]](COPYING)


## New Proposed Feature: “Import Highlights from a PDF File”
You want to sync PDF files to read on both your computer and your e-reader. Koreader offers a feature called “Write All Highlights into PDF File” that allows users to save highlights into a PDF file. When you copy this PDF file to your computer, the highlights created while reading with Koreader on the e-reader are retained. However, if you add additional highlights to the PDF on your computer and then transfer the file back to the e-reader, Koreader can only display these new highlights but cannot edit them. To address this limitation, I added a new function named “Import Highlights from a PDF File” to Koreader.

**Usage:**
1.	Copy the PDF file from your computer to your e-reader.
2.	Open the PDF file with Koreader.
3.	Open the Koreader menu.
4.	Select the second tab from the left.
5.	Choose “Highlights.”
6.	Select “Write Highlights into PDF.”
7.	Choose “On.”
8.	Choose “Import Highlights from This PDF File.”


## New Proposed Feature: “Highlight Navigation”
You want to quickly skim through pages containing important highlighted content. To facilitate this, you need a feature that allows easy reading and navigation between highlighted pages while skipping those without. Since Koreader currently lacks this functionality, I have introduced a new feature called “Highlight Navigation” to address this need.

**Configuration Steps:**
1.	Open a PDF file with Koreader.
2.	Open the Koreader menu.
3.	Select the third tab from the left.
4.	Choose “Taps and Gestures.”
5.	Select “Gesture Manager.”
6.	Choose “Tap Corner.”
7.	Select “Bottom Right.”
8.	Choose “Reader.”
9.	Select “Toggle Highlight Navigation.”

**Usage:**
Once the "Highlight Navigation" feature is configured:
•	Tap the bottom-right corner of the screen to toggle Highlight Navigation on or off.
•	When Highlight Navigation is on, tapping the right or left area of the screen will move to the next or previous page with highlights, skipping pages without highlights.
•	When Highlight Navigation is off, tapping the right or left area will function as usual, moving to the next or previous page sequentially.


## Screenshots

<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-menu.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-menu-thumbnail.png" alt="" width="200px"></a>
<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-footnotes.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-footnotes-thumbnail.png" alt="" width="200px"></a>
<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-dictionary.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-dictionary-thumbnail.png" alt="" width="200px"></a>


## Installation

[Download](https://github.com/tuanminhpham/koreaderx/releases)

Download for Android: 

koreaderx-2024.11-beta.apk 

SHA256: e45c7f0c6744f68f4bf1617f9b01bdffe9a8caa2627ac06ecd28d97116bdac13


## Development

[Setting up a build environment](doc/Building.md) •

