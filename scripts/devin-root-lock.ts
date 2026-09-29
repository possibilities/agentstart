/** Serialize snapshot registration and reaping for one Git root. */
import { createHash } from "node:crypto";
import { closeSync, constants, openSync } from "node:fs";
import { join } from "node:path";
import { dlopen, FFIType } from "bun:ffi";

const libc = dlopen(process.platform === "darwin" ? "/usr/lib/libSystem.B.dylib" : "libc.so.6", {
  flock: { args: [FFIType.i32, FFIType.i32], returns: FFIType.i32 },
});

export function lockDevinRoot(stateDir: string, root: string): () => void {
  const digest = createHash("sha256").update(root).digest("hex");
  // Keep this inode across runs: unlinking a lock file permits two holders on
  // different inodes at the same path. The state directory is private.
  const fd = openSync(join(stateDir, `${digest}.lock`), constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
  if (libc.symbols.flock(fd, 2) !== 0) {
    closeSync(fd);
    throw new Error(`could not lock Devin snapshot for ${root}`);
  }
  return () => closeSync(fd);
}
