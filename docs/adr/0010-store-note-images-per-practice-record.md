# Store note images as files scoped to a practice record

Note images belong to the current flow's `PracticeItem`, which represents one dated practice record. We store compressed image files in Application Support under that item's ID and derive the image count from those files. This keeps large image bytes out of SwiftData and avoids changing the shipped practice schema; the trade-off is that file writes and record updates cannot share a database transaction, so failed updates remove newly written files and explicit practice deletion or data reset removes stored images.
