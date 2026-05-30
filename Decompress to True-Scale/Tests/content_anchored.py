"""
Content-anchored uniform elastic approach:
Divide the opaque source region into the correct number of cells
based on pass dimensions, using as even a distribution as possible.
"""
import numpy as np
from PIL import Image
import os
import collections

base = os.path.dirname(os.path.abspath(__file__))


def find_opaque_bbox(arr):
    rows = np.any(arr[:, :, 3] > 0, axis=1)
    cols = np.any(arr[:, :, 3] > 0, axis=0)
    if not np.any(rows):
        return 0, 0, 0, 0
    r0 = np.argmax(rows)
    r1 = len(rows) - 1 - np.argmax(rows[::-1])
    c0 = np.argmax(cols)
    c1 = len(cols) - 1 - np.argmax(cols[::-1])
    return r0, r1, c0, c1


def distribute_cells(span, n_cells):
    """Distribute `span` pixels across `n_cells` as evenly as possible.
    Returns list of cell widths."""
    base_width = span // n_cells
    remainder = span - base_width * n_cells
    # Distribute remainder as evenly as possible
    widths = [base_width] * n_cells
    # Add 1 pixel to `remainder` cells, spread evenly
    if remainder > 0:
        step = n_cells / remainder
        for i in range(remainder):
            idx = int(i * step)
            widths[idx] += 1
    return widths


def detect_transitions(arr, axis, tolerance=0):
    """Detect colour transitions along an axis.
    tolerance: max per-channel difference to ignore (treats similar colours as same)."""
    h, w = arr.shape[:2]
    cuts = []
    if axis == 0:
        for y in range(h - 1):
            for x in range(w):
                if arr[y, x, 3] > 0 and arr[y+1, x, 3] > 0:
                    diff = np.abs(arr[y, x, :3].astype(int) - arr[y+1, x, :3].astype(int))
                    if np.max(diff) > tolerance:
                        cuts.append(y + 1)
                        break
    else:
        for x in range(w - 1):
            for y in range(h):
                if arr[y, x, 3] > 0 and arr[y, x+1, 3] > 0:
                    diff = np.abs(arr[y, x, :3].astype(int) - arr[y, x+1, :3].astype(int))
                    if np.max(diff) > tolerance:
                        cuts.append(x + 1)
                        break
    return cuts


def majority_vote(arr, y0, y1, x0, x1, min_opaque_ratio=0.3):
    """Most common opaque pixel in region. Returns transparent if below threshold."""
    region = arr[y0:y1, x0:x1]
    total_pixels = region.shape[0] * region.shape[1]
    opaque = region[region[:, :, 3] > 0]
    if len(opaque) == 0:
        return (0, 0, 0, 0)
    if len(opaque) < total_pixels * min_opaque_ratio:
        return (0, 0, 0, 0)
    counts = collections.Counter(map(tuple, opaque))
    return counts.most_common(1)[0][0]


def build_boundaries_from_widths(start, widths):
    """Convert start + widths list into (start, end) boundaries."""
    bounds = []
    pos = start
    for w in widths:
        bounds.append((pos, pos + w))
        pos += w
    return bounds


def content_anchored_resample(src_arr, target_h, target_w, pitch=None):
    """
    1. Find opaque bounding box in source
    2. Use row transitions to determine compression ratio
    3. Apply ratio to determine correct column count
    4. Anchor: bottom for rows, right-edge for columns
    """
    h, w = src_arr.shape[:2]
    if pitch is None:
        pitch = h / target_h
    r0, r1, c0, c1 = find_opaque_bbox(src_arr)
    row_span = r1 - r0 + 1
    col_span = c1 - c0 + 1
    print(f"  Source bbox: rows [{r0},{r1}] cols [{c0},{c1}]")
    print(f"  Spans: {row_span} rows, {col_span} cols")

    # Use transitions to determine row cell count
    row_cuts = detect_transitions(src_arr, 0)

    # Build initial row boundaries, subdividing any large gaps
    # (handles cases where uniform-colour regions hide transitions)
    initial_ratio = row_span / (len(row_cuts) + 1)
    row_bounds = []
    prev = r0
    for cut in row_cuts:
        gap = cut - prev
        if gap > initial_ratio * 1.5:
            n_sub = max(1, round(gap / initial_ratio))
            sub_width = gap / n_sub
            for k in range(n_sub):
                sub_start = int(prev + k * sub_width)
                sub_end = int(prev + (k + 1) * sub_width)
                row_bounds.append((sub_start, sub_end))
        else:
            row_bounds.append((prev, cut))
        prev = cut
    # Last segment
    gap = r1 + 1 - prev
    if gap > initial_ratio * 1.5:
        n_sub = max(1, round(gap / initial_ratio))
        sub_width = gap / n_sub
        for k in range(n_sub):
            sub_start = int(prev + k * sub_width)
            sub_end = int(prev + (k + 1) * sub_width)
            row_bounds.append((sub_start, sub_end))
    else:
        row_bounds.append((prev, r1 + 1))

    n_content_rows = len(row_bounds)
    print(f"  Row transitions: {len(row_cuts)} → {n_content_rows} row cells (after subdivision)")

    # Compression ratio from rows
    compression_ratio = row_span / n_content_rows
    print(f"  Compression ratio: {compression_ratio:.3f} px/cell (nominal pitch={pitch:.2f})")

    # Apply ratio to columns
    n_content_cols = round(col_span / compression_ratio)
    print(f"  Column cells: round({col_span}/{compression_ratio:.3f}) = {n_content_cols}")

    # Anchoring
    # Rows: bottom-anchored (content extends to last row)
    bottom_anchored = r1 >= h - compression_ratio * 1.5
    if bottom_anchored:
        row_target_start = target_h - n_content_rows
    else:
        # Centre-based: map source centre to target centre, derive start
        row_centre_source = (r0 + r1) / 2.0
        row_centre_target = row_centre_source / pitch
        row_target_start = round(row_centre_target - n_content_rows / 2.0)

    # Columns: centre-aligned based on source midpoint
    col_midpoint_source = (c0 + c1) / 2.0
    col_midpoint_target = col_midpoint_source / pitch
    col_target_start = round(col_midpoint_target - (n_content_cols - 1) / 2.0)

    print(f"  Anchoring: bottom={bottom_anchored}")
    print(f"  Row target start: {row_target_start}")
    print(f"  Col midpoint: src={col_midpoint_source} tgt={col_midpoint_target} start={col_target_start} (n={n_content_cols})")

    # Column boundaries: use transitions where available, interpolate gaps
    col_cuts = detect_transitions(src_arr, 1, tolerance=40)
    # Filter to only cuts within the opaque region
    col_cuts = [c for c in col_cuts if c0 < c <= c1]

    if len(col_cuts) >= n_content_cols // 2:
        # Build boundaries from transitions, subdividing large gaps
        col_bounds = []
        prev = c0
        for cut in col_cuts:
            gap = cut - prev
            if gap > compression_ratio * 1.5:
                # Subdivide this gap
                n_sub = max(1, round(gap / compression_ratio))
                sub_width = gap / n_sub
                for k in range(n_sub):
                    sub_start = int(prev + k * sub_width)
                    sub_end = int(prev + (k + 1) * sub_width)
                    col_bounds.append((sub_start, sub_end))
            else:
                col_bounds.append((prev, cut))
            prev = cut
        # Last segment after final transition
        gap = c1 + 1 - prev
        if gap > compression_ratio * 1.5:
            n_sub = max(1, round(gap / compression_ratio))
            sub_width = gap / n_sub
            for k in range(n_sub):
                sub_start = int(prev + k * sub_width)
                sub_end = int(prev + (k + 1) * sub_width)
                col_bounds.append((sub_start, sub_end))
        else:
            col_bounds.append((prev, c1 + 1))

        # Adjust count to match n_content_cols
        while len(col_bounds) > n_content_cols:
            # Merge smallest adjacent pair
            min_idx = min(range(len(col_bounds)),
                         key=lambda i: col_bounds[i][1] - col_bounds[i][0])
            if min_idx < len(col_bounds) - 1:
                merged = (col_bounds[min_idx][0], col_bounds[min_idx + 1][1])
                col_bounds = col_bounds[:min_idx] + [merged] + col_bounds[min_idx + 2:]
            elif min_idx > 0:
                merged = (col_bounds[min_idx - 1][0], col_bounds[min_idx][1])
                col_bounds = col_bounds[:min_idx - 1] + [merged] + col_bounds[min_idx + 1:]
            else:
                break
        while len(col_bounds) < n_content_cols:
            # Split largest cell
            max_idx = max(range(len(col_bounds)),
                         key=lambda i: col_bounds[i][1] - col_bounds[i][0])
            s, e = col_bounds[max_idx]
            mid = (s + e) // 2
            col_bounds = col_bounds[:max_idx] + [(s, mid), (mid, e)] + col_bounds[max_idx + 1:]
    else:
        # Not enough transitions - use uniform distribution
        col_widths = distribute_cells(col_span, n_content_cols)
        col_bounds = build_boundaries_from_widths(c0, col_widths)

    print(f"  Final: {len(row_bounds)} rows, {len(col_bounds)} cols")
    print(f"  Row bounds [0:3]: {row_bounds[:3]}")
    print(f"  Col bounds [0:3]: {col_bounds[:3]}")

    # Create output
    output = np.zeros((target_h, target_w, 4), dtype=np.uint8)
    for i, (rs, re) in enumerate(row_bounds):
        ty = row_target_start + i
        if ty < 0 or ty >= target_h:
            continue
        for j, (cs, ce) in enumerate(col_bounds):
            tx = col_target_start + j
            if tx < 0 or tx >= target_w:
                continue
            pixel = majority_vote(src_arr, rs, re, cs, ce)
            output[ty, tx] = pixel

    return output


tests = {
    "Test 1": ("Test 1/Allison Token V1 001 Original.png", "Test 1/Pass/Allison Token V1 Correct 001.png"),
    "Test 2": ("Test 2/Colm Theron Token V3 Original 001.png", "Test 2/Pass/Colm Theron V1 Correct 001.png"),
    "Test 3": ("Test 3/Jardon Nash Token V1 Original 001.png", "Test 3/Pass/Jardon Nash Token V1 Correct 001.png"),
    "Test 4": ("Test 4/Squiggles Original 001.png", "Test 4/Pass/Squiggles Token V1 001 Pass001.png"),
    "Test 5": ("Test 5/Mudcrab - Alistar001 Original.png", "Test 5/Pass/Alistar Token V1 001 Pass001.png"),
    "Test 6": ("Test 6/Astantra Token V1 Original 001.png", "Test 6/Pass/Astantra Token V1 002.png"),
    "Test 7": ("Test 7/Targaen Forerunner Original 001.png", "Test 7/Pass/Targaen Forerunner.png"),
}

for test_name, (src_file, pass_file) in tests.items():
    src_full = os.path.join(base, src_file)
    pass_full = os.path.join(base, pass_file)
    if not os.path.exists(src_full) or not os.path.exists(pass_full):
        print(f"\n=== {test_name}: SKIPPED (missing files) ===")
        continue

    print(f"\n=== Content-Anchored Elastic Grid - {test_name} ===")
    src_img = np.array(Image.open(src_full).convert("RGBA"))
    pas_img = np.array(Image.open(pass_full).convert("RGBA"))
    th_t, tw_t = pas_img.shape[:2]

    output = content_anchored_resample(src_img, th_t, tw_t)

    # Compare
    mismatches = 0
    details = []
    for y in range(th_t):
        for x in range(tw_t):
            if not np.array_equal(output[y, x], pas_img[y, x]):
                mismatches += 1
                if len(details) < 10:
                    details.append((x, y, tuple(output[y, x]), tuple(pas_img[y, x])))

    print(f"\n  Result: {mismatches} mismatches")
    if 0 < mismatches <= 20:
        for x, y, op, pp in details:
            print(f"    ({x},{y}): out={op} pass={pp}")

    # Save output
    out_path = os.path.join(base, test_name, "elastic_output.png")
    Image.fromarray(output).save(out_path)
    print(f"  Saved: {test_name}/elastic_output.png")
