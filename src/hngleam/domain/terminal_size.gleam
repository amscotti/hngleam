//// The size of the terminal the application is drawing into.

pub opaque type TerminalSize {
  TerminalSize(width: Int, height: Int)
}

/// The narrowest window the layout is designed for.
pub const minimum_width: Int = 50

/// The shortest window the layout is designed for.
pub const minimum_height: Int = 14

/// Build a size, treating non-positive measurements as one cell so that the
/// layout maths never has to deal with negative widths.
pub fn make(width: Int, height: Int) -> TerminalSize {
  TerminalSize(width: int_max(width, 1), height: int_max(height, 1))
}

/// The number of columns.
pub fn width(size: TerminalSize) -> Int {
  let TerminalSize(width:, ..) = size
  width
}

/// The number of rows.
pub fn height(size: TerminalSize) -> Int {
  let TerminalSize(height:, ..) = size
  height
}

/// True when the window is too small for the layout to be readable.
pub fn too_small(size: TerminalSize) -> Bool {
  width(size) < minimum_width || height(size) < minimum_height
}

fn int_max(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}
