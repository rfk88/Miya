#!/usr/bin/env python3
"""
Final cleanup script to remove all remaining duplicate components from DashboardView.swift.
"""

def remove_lines(lines, start_line, end_line):
    """Remove lines from start_line to end_line (1-indexed, inclusive)."""
    start_idx = start_line - 1
    end_idx = end_line
    return lines[:start_idx] + lines[end_idx:]

def main():
    input_file = "/Users/ramikaawach/Desktop/Miya/Miya Health/DashboardView.swift"
    output_file = "/Users/ramikaawach/Desktop/Miya/Miya Health/DashboardView_final.swift"
    
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    print(f"Original file: {len(lines)} lines")
    
    # Remove sidebar components (lines 2033-3177 based on the MARK comment before AccountSidebarView)
    # Line 2033 is "// MARK: - ACCOUNT SIDEBAR VIEW"
    # We need to find where ManageMembersView ends
    
    # First, let's find the exact end of ManageMembersView by looking for the next significant marker
    # Looking at line 3177, it should be around there
    
    # Remove orphaned FamilyNotificationItem code (lines 3191-3391)
    # But after removing the sidebar section, line numbers will shift
    
    # Strategy: Remove in reverse order to preserve line numbers
    # 1. First remove the orphaned code (3191-3391)
    # 2. Then remove the sidebar section (2033-3177)
    
    # Let's be more precise - find the closing brace of ManageMembersView
    # and the orphaned code section
    
    # Section 1: Orphaned FamilyNotificationItem code
    # Starts at line 3191 with "case trend(TrendInsight)"
    # Ends at line 3391 with "}"
    
    # Section 2: Sidebar components
    # Starts at line 2033 with "// MARK: - ACCOUNT SIDEBAR VIEW"
    # Need to find where it ends - should be right before the orphaned code
    
    # Let's look for the "fileprivate func initials" which appears to be at line 3171
    # So sidebar section is lines 2033-3177
    
    # Actually, let me search for these markers in the file
    orphaned_start = None
    orphaned_end = None
    sidebar_start = None
    sidebar_end = None
    
    for i, line in enumerate(lines):
        if "case trend(TrendInsight)" in line and orphaned_start is None:
            orphaned_start = i + 1  # Convert to 1-indexed
            print(f"Found orphaned code start at line {orphaned_start}")
        
        if orphaned_start and "private static func makeInitials" in line and orphaned_end is None:
            # Find the closing brace of this orphaned section
            # It should be a few lines after makeInitials
            for j in range(i, min(i + 10, len(lines))):
                if lines[j].strip() == "}":
                    orphaned_end = j + 1  # Convert to 1-indexed
                    print(f"Found orphaned code end at line {orphaned_end}")
                    break
        
        if "// MARK: - ACCOUNT SIDEBAR VIEW" in line and sidebar_start is None:
            sidebar_start = i + 1  # Convert to 1-indexed
            print(f"Found sidebar start at line {sidebar_start}")
        
        if sidebar_start and "fileprivate func initials(from name: String)" in line and sidebar_end is None:
            # Find the closing brace of this function
            for j in range(i, min(i + 10, len(lines))):
                if lines[j].strip() == "}":
                    sidebar_end = j + 1  # Convert to 1-indexed
                    print(f"Found sidebar end at line {sidebar_end}")
                    break
    
    if not all([orphaned_start, orphaned_end, sidebar_start, sidebar_end]):
        print("ERROR: Could not find all sections")
        print(f"orphaned_start={orphaned_start}, orphaned_end={orphaned_end}")
        print(f"sidebar_start={sidebar_start}, sidebar_end={sidebar_end}")
        return
    
    # Remove in reverse order to preserve line numbers
    print(f"\nRemoving orphaned code (lines {orphaned_start}-{orphaned_end}): {orphaned_end - orphaned_start + 1} lines")
    lines = remove_lines(lines, orphaned_start, orphaned_end)
    
    # Adjust sidebar_end since we removed lines before it
    lines_removed = orphaned_end - orphaned_start + 1
    if sidebar_end > orphaned_start:
        sidebar_end -= lines_removed
    
    print(f"Removing sidebar section (lines {sidebar_start}-{sidebar_end}): {sidebar_end - sidebar_start + 1} lines")
    lines = remove_lines(lines, sidebar_start, sidebar_end)
    
    # Write output
    with open(output_file, 'w') as f:
        f.writelines(lines)
    
    print(f"\nFinal file: {len(lines)} lines")
    print(f"Total removed: {len(open(input_file).readlines()) - len(lines)} lines")
    print(f"\nOutput written to: {output_file}")

if __name__ == "__main__":
    main()
