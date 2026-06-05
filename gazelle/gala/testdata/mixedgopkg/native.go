package mixedgopkg

import (
	"fmt"

	"martianoff/gala/go_interop"
)

// Native is a hand-written Go helper sharing the package with the .gala
// sources. The extension folds it into the gala_library's go_srcs, and its
// imports (the gala go_interop dep; the fmt stdlib dep is dropped by the
// resolver) join the library's dep set.
func Native() string { return fmt.Sprint(go_interop.Something) }
