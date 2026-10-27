import Testing

/// Every suite that renders a view through `ImageRenderer` or draws a hosted panel in a window is nested in this one,
/// so no two of them draw at once.
///
/// `ImageRenderer` turns the main run loop while it renders, so another test's render on the main actor can start in
/// between, and each render may then hand back the other's pixels. `.serialized` applies to every nested suite, while
/// suites outside this one keep running in parallel.
@Suite(.serialized) enum RenderingTests {}
