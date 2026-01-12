#!/usr/bin/env python3
"""
Script to remove duplicate components from DashboardView.swift that have been extracted to separate files.
"""

def remove_struct_definition(lines, start_line_num):
    """
    Remove a struct definition starting at start_line_num.
    Returns the index of the line after the struct ends.
    """
    brace_count = 0
    started = False
    i = start_line_num
    
    while i < len(lines):
        line = lines[i]
        
        # Count braces
        for char in line:
            if char == '{':
                brace_count += 1
                started = True
            elif char == '}':
                brace_count -= 1
                
        # If we've started and braces are balanced, we're done
        if started and brace_count == 0:
            return i + 1
            
        i += 1
    
    return i

def main():
    input_file = "/Users/ramikaawach/Desktop/Miya/Miya Health/DashboardView.swift"
    output_file = "/Users/ramikaawach/Desktop/Miya/Miya Health/DashboardView_cleaned.swift"
    
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    # Find structs to remove (line numbers are 0-indexed in Python, but 1-indexed in the file)
    structs_to_remove = [
        ("private struct FamilyNotificationsCard", 3393 - 1),
        ("private struct FamilyNotificationDetailSheet", 3469 - 1),
        ("private struct FamilyVitalityInsightsCard", 5361 - 1),
        ("private struct TrendInsightCard", 5555 - 1),
        ("private struct RecommendationRowView", 5646 - 1),
        ("private struct FamilyHelpActionCard", 5693 - 1),
        ("private struct MiyaInsightChatSheet", 5774 - 1),
    ]
    
    # Mark lines to remove
    lines_to_remove = set()
    
    for struct_name, start_idx in structs_to_remove:
        # Verify this is the right line
        if struct_name in lines[start_idx]:
            end_idx = remove_struct_definition(lines, start_idx)
            for i in range(start_idx, end_idx):
                lines_to_remove.add(i)
            print(f"Marked {struct_name} for removal (lines {start_idx+1}-{end_idx})")
        else:
            print(f"WARNING: Could not find {struct_name} at line {start_idx+1}")
            print(f"  Found instead: {lines[start_idx].strip()}")
    
    # Write output, skipping marked lines
    with open(output_file, 'w') as f:
        for i, line in enumerate(lines):
            if i not in lines_to_remove:
                f.write(line)
    
    print(f"\nRemoved {len(lines_to_remove)} lines")
    print(f"Original: {len(lines)} lines")
    print(f"Cleaned: {len(lines) - len(lines_to_remove)} lines")
    print(f"\nOutput written to: {output_file}")

if __name__ == "__main__":
    main()
