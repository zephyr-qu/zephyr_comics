# Zephyr Comics Domain

Zephyr Comics is a personal, offline Android comic reader. This glossary defines the product language used by requirements, code, tests, and UI copy.

## Library

**Comic**:
A single local CBZ or ZIP archive represented as one item in the library.
_Avoid_: Book, manga file, chapter

**Library Root**:
The single user-selected filesystem directory whose descendants are scanned for comics.
_Avoid_: Scan path, source folder, collection

**Library Entry**:
A derived record for a comic containing its path, title, cover, page count, format, and reading summary. The comic file remains the source of truth.
_Avoid_: Comic file, database book

**Derived Cover**:
A rebuildable thumbnail selected from `ComicInfo.xml` front-cover metadata or the first naturally sorted page.
_Avoid_: Original cover, cached comic

## Reading

**Page**:
A supported JPEG, PNG, or WebP image entry in a comic after filtering and natural sorting.
_Avoid_: Archive entry, chapter page

**Reading Progress**:
The last current page recorded for a comic, independent from whether the comic is finished or appears in history.
_Avoid_: History, bookmark

**Reading History Entry**:
A recency record showing that a comic was opened for reading. Removing it does not remove reading progress or bookmarks.
_Avoid_: Reading progress

**Bookmark**:
A saved page in one comic that can be revisited or removed.
_Avoid_: Favorite, note

**Finished Comic**:
A comic whose last page has become the current displayed page. Restarting from page one does not immediately clear this state.
_Avoid_: Completed archive, read progress 100 percent

**Reader Mode**:
One of the five supported page-navigation layouts: single-page vertical, left-to-right, right-to-left, continuous, or webtoon.
_Avoid_: Chapter mode, double-page mode

## Storage

**Derived Cache**:
Rebuildable application-owned data such as covers, thumbnails, and temporary decode artifacts. It never includes the user's source comic.
_Avoid_: Library, comic backup
