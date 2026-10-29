package calcantlr

import (
	"testing"

	"github.com/antlr4-go/antlr/v4"

	"github.com/martianoff/rules-gala/e2e/galop/calc"
)

// The converter galop writes with the nativePackage define turns ANTLR's tree,
// and the antlr flavor's, into the native flavor's tree of the same input.
func TestConverter(t *testing.T) {
	src := "1 + 2 - 30"
	native, err := calc.ParseProg(calc.CalcLex(src))
	if err != nil {
		t.Fatal(err)
	}
	want := native.ToStringTree()

	stream := antlr.NewCommonTokenStream(NewCalcLexer(antlr.NewInputStream(src)), antlr.TokenDefaultChannel)
	prog := NewCalcParser(stream).Prog()
	_, root := CalcToNative(prog, stream, src)
	if got := root.ToStringTree(); got != want {
		t.Errorf("converted ANTLR tree %s, want %s", got, want)
	}

	// From galop 0.2.5, ToNativeContexts also returns each node's context, by
	// node index, the root's last.
	_, croot, ctxs := CalcToNativeContexts(prog, stream, src)
	if got := croot.ToStringTree(); got != want {
		t.Errorf("ToNativeContexts tree %s, want %s", got, want)
	}
	if len(ctxs) == 0 || ctxs[len(ctxs)-1] != prog {
		t.Errorf("ToNativeContexts: the last of %d contexts is not the root", len(ctxs))
	}
	for i, c := range ctxs {
		if c == nil {
			t.Errorf("ToNativeContexts: node %d has no context", i)
		}
	}

	fstream := antlr.NewCommonTokenStream(NewCalcGalopLexer(antlr.NewInputStream(src)), antlr.TokenDefaultChannel)
	ctx, err := NewCalcGalopParser(fstream).Prog()
	if err != nil {
		t.Fatal(err)
	}
	_, froot := CalcToNative(ctx, fstream, src)
	if got := froot.ToStringTree(); got != want {
		t.Errorf("converted antlr-flavor tree %s, want %s", got, want)
	}
}
