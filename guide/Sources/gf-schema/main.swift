// Prints Lume GF's iCloud layout (cloudkit/schema.ckdb). CI: `swift run --package-path guide gf-schema`.
import SyncCore

print(GFCloudSchema.ckdb(), terminator: "")
