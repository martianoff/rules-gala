package mixedgopkg

// Native is a hand-written Go helper bundled into the same package as the
// .gala sources. Its presence makes this a mixed GALA/Go package, which must
// be wired via gala_bootstrap_transpile + go_library rather than gala_library.
func Native() int { return 42 }
