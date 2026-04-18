import Foundation

// MARK: - Calibration Transform

/// Computes and applies a perspective transform from 4 camera-space points
/// to 4 screen-space points for accurate cursor mapping.
struct CalibrationTransform: Sendable {
    /// 3x3 perspective transform matrix stored in row-major order (9 elements)
    let matrix: [Double]

    /// Apply the transform to a normalized camera point to get screen coordinates
    func apply(to point: CGPoint) -> CGPoint {
        let x = point.x
        let y = point.y
        let m = matrix

        let w = m[6] * Double(x) + m[7] * Double(y) + m[8]
        guard abs(w) > 1e-10 else { return point }

        let outX = (m[0] * Double(x) + m[1] * Double(y) + m[2]) / w
        let outY = (m[3] * Double(x) + m[4] * Double(y) + m[5]) / w

        return CGPoint(x: outX, y: outY)
    }

    /// Compute a perspective transform from 4 source points to 4 destination points.
    /// Uses the DLT (Direct Linear Transform) method.
    static func compute(
        from sourcePoints: [CGPoint],
        to destPoints: [CGPoint]
    ) -> CalibrationTransform? {
        guard sourcePoints.count == 4, destPoints.count == 4 else { return nil }

        // Build the 8x8 system of equations for homography
        // For each point correspondence (x,y) -> (x',y'):
        //   x'(h7*x + h8*y + 1) = h1*x + h2*y + h3
        //   y'(h7*x + h8*y + 1) = h4*x + h5*y + h6
        var A = [Double](repeating: 0, count: 64)  // 8x8 matrix
        var b = [Double](repeating: 0, count: 8)    // 8x1 vector

        for i in 0..<4 {
            let sx = Double(sourcePoints[i].x)
            let sy = Double(sourcePoints[i].y)
            let dx = Double(destPoints[i].x)
            let dy = Double(destPoints[i].y)

            let row1 = i * 2
            let row2 = i * 2 + 1

            // Row for x' equation
            A[row1 * 8 + 0] = sx
            A[row1 * 8 + 1] = sy
            A[row1 * 8 + 2] = 1
            A[row1 * 8 + 3] = 0
            A[row1 * 8 + 4] = 0
            A[row1 * 8 + 5] = 0
            A[row1 * 8 + 6] = -dx * sx
            A[row1 * 8 + 7] = -dx * sy
            b[row1] = dx

            // Row for y' equation
            A[row2 * 8 + 0] = 0
            A[row2 * 8 + 1] = 0
            A[row2 * 8 + 2] = 0
            A[row2 * 8 + 3] = sx
            A[row2 * 8 + 4] = sy
            A[row2 * 8 + 5] = 1
            A[row2 * 8 + 6] = -dy * sx
            A[row2 * 8 + 7] = -dy * sy
            b[row2] = dy
        }

        // Solve Ax = b using Gaussian elimination with partial pivoting
        guard solveLinearSystem(A: &A, b: &b, n: 8) else { return nil }

        // b now contains the solution [h1..h8], h9 = 1
        let matrix = [b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], 1.0]
        return CalibrationTransform(matrix: matrix)
    }

    /// Simple linear mapping (no perspective correction) as a fallback
    static func simpleLinearMapping(
        screenWidth: Double,
        screenHeight: Double,
        sensitivity: Double = 1.0
    ) -> CalibrationTransform {
        // Map (0,0)-(1,1) camera space to (0,0)-(screenWidth,screenHeight)
        // With sensitivity scaling from center
        let sx = screenWidth * sensitivity
        let sy = screenHeight * sensitivity
        let ox = (screenWidth - sx) / 2.0
        let oy = (screenHeight - sy) / 2.0

        return CalibrationTransform(matrix: [
            sx,  0,  ox,
            0,  sy,  oy,
            0,   0,   1
        ])
    }
}

// MARK: - Gaussian Elimination (replaces deprecated LAPACK dgesv_)

/// Solves A·x = b in-place (result stored in b). A is row-major n×n.
/// Returns false if the matrix is singular or poorly conditioned.
private func solveLinearSystem(A: inout [Double], b: inout [Double], n: Int) -> Bool {
    var pivot = Array(0..<n)   // row permutation

    for col in 0..<n {
        // Find pivot row (largest absolute value in this column)
        var maxVal = 0.0
        var maxRow = col
        for row in col..<n {
            let val = abs(A[pivot[row] * n + col])
            if val > maxVal { maxVal = val; maxRow = row }
        }
        guard maxVal > 1e-12 else { return false }   // singular
        pivot.swapAt(col, maxRow)

        let p = pivot[col]
        let diag = A[p * n + col]

        // Eliminate rows below
        for row in (col + 1)..<n {
            let r = pivot[row]
            let factor = A[r * n + col] / diag
            guard factor.isFinite else { return false }
            for k in col..<n {
                A[r * n + k] -= factor * A[p * n + k]
            }
            b[r] -= factor * b[p]
        }
    }

    // Back substitution
    for row in stride(from: n - 1, through: 0, by: -1) {
        let r = pivot[row]
        var sum = b[r]
        for k in (row + 1)..<n {
            sum -= A[r * n + k] * b[pivot[k]]
        }
        let diag = A[r * n + row]
        guard abs(diag) > 1e-12 else { return false }
        b[r] = sum / diag
    }

    // Reorder b into natural order
    var result = [Double](repeating: 0, count: n)
    for i in 0..<n { result[i] = b[pivot[i]] }
    b = result
    return true
}
