import Observation
@Observable final class S {
    var x: Int = 0 { didSet { x = min(x, 10); print("didSet", x) } }
    var y: Int = 1 { didSet { print("y didSet", oldValue, "->", y) } }
}
let s = S()
s.x = 50
print("x =", s.x)
s.y = 2
