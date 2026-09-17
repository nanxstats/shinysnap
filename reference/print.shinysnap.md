# Print, format, and coerce snapshot objects

[`print()`](https://rdrr.io/r/base/print.html) shows a compact summary:
app name and version, creation time, and the number and names of inputs,
values, and attachments.
[`format()`](https://rdrr.io/r/base/format.html) returns the same lines
as a character vector. [`as.list()`](https://rdrr.io/r/base/list.html)
drops the class and returns the underlying list.

## Usage

``` r
# S3 method for class 'shinysnap'
print(x, ...)

# S3 method for class 'shinysnap'
format(x, ...)

# S3 method for class 'shinysnap'
as.list(x, ...)
```

## Arguments

- x:

  A snapshot object.

- ...:

  Ignored.

## Value

[`print()`](https://rdrr.io/r/base/print.html) returns `x` invisibly;
[`format()`](https://rdrr.io/r/base/format.html) a character vector;
[`as.list()`](https://rdrr.io/r/base/list.html) a plain list.

## Examples

``` r
snap <- snap_unserialize('{
  "format": 1,
  "app": {"name": "myapp", "version": "2.4.1"},
  "created": "2026-09-16T18:22:03Z",
  "inputs": {"n": 100, "rate": 0.025}
}')
print(snap)
#> <shinysnap>
#>   app:         myapp (version 2.4.1)
#>   created:     2026-09-16T18:22:03Z
#>   inputs:      2 (n, rate)
#>   values:      0
#>   attachments: 0
names(as.list(snap))
#> [1] "format"      "app"         "created"     "producer"    "inputs"     
#> [6] "values"      "bindings"    "attachments" "meta"       
```
