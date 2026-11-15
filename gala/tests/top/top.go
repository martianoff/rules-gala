package top

import (
	"example.com/mid"

	_ "example.com/galapkg"
)

func Top() mid.T { return mid.Mid() }
