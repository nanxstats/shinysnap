# Access the parts of a snapshot

`snap_inputs()` returns the captured input values (a named list keyed by
fully namespaced input ids), `snap_values()` the server-side values, and
`snap_meta()` the user-supplied metadata. See
[shinysnap-package](https://nanx.me/shinysnap/reference/shinysnap-package.md)
for the layout of the object.

## Usage

``` r
snap_inputs(x)

snap_values(x)

snap_meta(x)
```

## Arguments

- x:

  A snapshot object.

## Value

A named list, possibly empty.

## Examples

``` r
snap <- snap_unserialize('{
  "format": 1,
  "inputs": {"n": 100, "rate": 0.025},
  "values": {"prefs": {"digits": 3, "scientific": false}},
  "meta": {"note": "baseline scenario"}
}')
snap_inputs(snap)
#> $n
#> [1] 100
#> 
#> $rate
#> [1] 0.025
#> 
snap_values(snap)
#> $prefs
#> $prefs$digits
#> [1] 3
#> 
#> $prefs$scientific
#> [1] FALSE
#> 
#> 
snap_meta(snap)
#> $note
#> [1] "baseline scenario"
#> 
```
