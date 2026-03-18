# OpenSCAD Language Reference (v2021.01)

## Syntax & Declaration
```openscad
var = value;                              // variable assignment
var = cond ? value_if_true : value_if_false;  // ternary
var = function (x) x + x;                // function literal
module name(params) { ... }              // module definition
function name(params) = expr;            // function definition
include <file.scad>                       // include (executes top-level code)
use <file.scad>                           // import (only modules/functions)
```

## Constants
- `undef` — undefined value
- `PI` — 3.14159...

## Special Variables
| Variable | Purpose |
|----------|---------|
| `$fn` | Fixed number of segments for circles/spheres |
| `$fa` | Minimum angle per segment |
| `$fs` | Minimum segment size |
| `$t` | Animation step (0–1) |
| `$vpr` | Viewport rotation |
| `$vpt` | Viewport translation |
| `$vpd` | Viewport distance |
| `$vpf` | Viewport field of view |
| `$children` | Number of child modules |
| `$preview` | `true` in preview (F5), `false` in render (F6) |

## Modifier Characters
- `*` — disable (don't render)
- `!` — show only this
- `#` — highlight/debug (transparent red)
- `%` — transparent/background

## 3D Primitives
```openscad
cube(size, center=false)                   // cube([w,d,h]) or cube(s)
sphere(r=radius)                           // sphere(d=diameter)
cylinder(h, r=radius, center=false)        // cylinder(h, d=diameter)
cylinder(h, r1, r2, center=false)          // cone/tapered cylinder
polyhedron(points, faces, convexity)        // custom solid
```

## 2D Primitives
```openscad
circle(r=radius)                           // circle(d=diameter)
square(size, center=false)                 // square([w,h])
polygon(points, paths)                      // 2D polygon
text(t, size=10, font, halign, valign, spacing)  // text string
```

## 2D → 3D Extrusion
```openscad
linear_extrude(height, center, twist, slices, scale)
    circle(10);                            // extrude 2D to 3D

rotate_extrude(angle=360, convexity)
    translate([20,0]) circle(5);           // lathe/revolve

surface(file="heightmap.dat", center)       // heightmap to 3D
```

## Transformations
```openscad
translate([x, y, z])                       // move
rotate([x, y, z])                          // rotate (degrees)
rotate(angle, [x, y, z])                   // rotate around axis
scale([x, y, z])                           // scale
resize([x, y, z], auto)                    // resize to exact dimensions
mirror([x, y, z])                          // mirror across plane
multmatrix(m)                              // 4x4 matrix transform
color("name", alpha)                       // color("red"), color("#ff0000")
color([r, g, b, a])                        // color by RGBA (0-1)
offset(r=radius)                           // 2D offset (round)
offset(delta=dist, chamfer=false)          // 2D offset (sharp)
```

## Boolean Operations
```openscad
union() { a(); b(); }                      // combine (A + B)
difference() { a(); b(); }                // subtract (A - B)
intersection() { a(); b(); }              // overlap only (A ∩ B)
```

## Advanced Operations
```openscad
hull() { a(); b(); }                       // convex hull
minkowski() { a(); b(); }                 // Minkowski sum (slow!)
render(convexity) { ... }                  // force CGAL render (cache)
projection(cut=false) { ... }             // 3D → 2D projection
```

## Import / Export
```openscad
import("file.stl")                         // import STL, OFF, AMF, 3MF
import("file.dxf")                         // import 2D DXF
import("file.svg")                         // import 2D SVG
```

## Flow Control
```openscad
if (condition) { ... } else { ... }
for (i = [0:10]) { ... }                  // range [start:end]
for (i = [0:2:10]) { ... }                // range [start:step:end]
for (i = [1, 5, 7]) { ... }               // list iteration
for (i = [...], j = [...]) { ... }         // nested loops
intersection_for(i = [...]) { ... }        // intersection across iterations
let (a = expr) { ... }                     // local variable scope
```

## List Comprehensions
```openscad
list = [ for (i = [0:10]) i * 2 ];                    // generate
list = [ for (i = [0:10]) if (i % 2 == 0) i ];        // filter
list = [ for (i = [0:10]) let (x = i*i) x ];           // with let
list = [ each sublist ];                                // flatten
```

## Math Functions
| Function | Description |
|----------|-------------|
| `abs(x)` | Absolute value |
| `sign(x)` | Sign (-1, 0, 1) |
| `sin(x)`, `cos(x)`, `tan(x)` | Trig (degrees) |
| `asin(x)`, `acos(x)`, `atan(x)` | Inverse trig |
| `atan2(y, x)` | Two-argument arctangent |
| `floor(x)`, `ceil(x)`, `round(x)` | Rounding |
| `ln(x)`, `log(x)` | Natural / base-10 log |
| `pow(base, exp)` | Power |
| `sqrt(x)` | Square root |
| `exp(x)` | e^x |
| `min(a,b,...)`, `max(a,b,...)` | Min/max |
| `norm(v)` | Vector magnitude |
| `cross(v1, v2)` | Cross product |
| `rands(min, max, count)` | Random numbers |
| `len(x)` | Length of list/string |

## String Functions
| Function | Description |
|----------|-------------|
| `str(...)` | Concatenate to string |
| `chr(code)` | ASCII code → character |
| `ord(char)` | Character → ASCII code |
| `search(needle, haystack)` | Search in list/string |

## Type Testing
```openscad
is_undef(x)   is_bool(x)    is_num(x)
is_string(x)  is_list(x)    is_function(x)
```

## Other Functions
```openscad
echo("msg", var)                           // debug output
assert(condition, "message")               // assertion
concat(list1, list2)                       // concatenate lists
lookup(key, [[k,v], ...])                  // table lookup
children(idx)                              // access child N of module
parent_module(idx)                         // access parent module name
version()                                  // OpenSCAD version string
```

## Operators
| Type | Operators |
|------|-----------|
| Arithmetic | `+` `-` `*` `/` `%` `^` |
| Relational | `<` `<=` `==` `!=` `>=` `>` |
| Logical | `&&` `\|\|` `!` |
| Indexing | `list[i]` `list.x` `list.y` `list.z` |

## Tips for AI-Generated Code
- **Always set `$fn`** for predictable circle resolution
- **Use `center=true`** when building symmetric objects with difference()
- **Add 0.01mm epsilon** to boolean cuts to avoid coplanar Z-fighting:
  ```openscad
  difference() {
      cube([10, 10, 10]);
      translate([-0.01, 2, 2])
          cube([10.02, 6, 6]);  // slightly larger to ensure clean cut
  }
  ```
- **Modules for reuse**: parameterize everything, compose with modules
- **Comments**: explain the "why", dimensions in mm
- **Print orientation**: think about which face goes on the build plate
- **Manifold check**: all boolean operands must overlap; no coincident faces
