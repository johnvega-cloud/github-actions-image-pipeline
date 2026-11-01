// A tiny HTTP server: it only exists so the pipeline has something to build.
package main

import (
	"fmt"
	"net/http"
	"runtime"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "hello from %s/%s\n", runtime.GOOS, runtime.GOARCH)
	})
	http.ListenAndServe(":8080", nil)
}
