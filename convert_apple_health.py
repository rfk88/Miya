#!/usr/bin/env python3
"""
Convert Apple Health XML export to Vitality Score CSV
Usage: python convert_apple_health.py export.xml
Output: vitality_data.csv
"""

from extractor import Extractor
import csv
from datetime import datetime
from collections import defaultdict
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: python convert_apple_health.py <export.xml>")
        sys.exit(1)
    
    xml_file = sys.argv[1]
    
    # Load Apple Health XML
    print(f"Loading {xml_file}...")
    extractor = Extractor(xml_file)
    
    # Get available record types
    print("\nAvailable record types:")
    record_types = extractor.get_record_types()
    health_types = [rt for rt in record_types if any(keyword in rt for keyword in ['Sleep', 'Steps', 'HeartRate', 'Variability'])]
    for rt in health_types:
        print(f"  - {rt}")
    
    # Extract metrics
    print("\nExtracting metrics...")
    sleep_records = extractor.get_records("HKCategoryTypeIdentifierSleepAnalysis")
    steps_records = extractor.get_records("HKQuantityTypeIdentifierStepCount")
    hrv_records = extractor.get_records("HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
    resting_hr_records = extractor.get_records("HKQuantityTypeIdentifierRestingHeartRate")
    
    print(f"  Sleep records: {len(sleep_records)}")
    print(f"  Steps records: {len(steps_records)}")
    print(f"  HRV records: {len(hrv_records)}")
    print(f"  Resting HR records: {len(resting_hr_records)}")
    
    # Aggregate by date
    daily_data = defaultdict(lambda: {'sleep': 0, 'steps': 0, 'hrv': [], 'resting_hr': []})
    
    # Process sleep (sum hours per day, only asleep time)
    for record in sleep_records:
        if record.get('value') == 'HKCategoryValueSleepAnalysisAsleep':
            date = record['startDate'][:10]
            start = datetime.fromisoformat(record['startDate'].replace('Z', '+00:00'))
            end = datetime.fromisoformat(record['endDate'].replace('Z', '+00:00'))
            hours = (end - start).total_seconds() / 3600
            daily_data[date]['sleep'] += hours
    
    # Process steps (sum per day)
    for record in steps_records:
        date = record['startDate'][:10]
        steps = float(record.get('value', 0))
        daily_data[date]['steps'] += steps
    
    # Process HRV (average per day)
    for record in hrv_records:
        date = record['startDate'][:10]
        hrv = float(record.get('value', 0))
        daily_data[date]['hrv'].append(hrv)
    
    # Process resting HR (average per day)
    for record in resting_hr_records:
        date = record['startDate'][:10]
        rhr = float(record.get('value', 0))
        daily_data[date]['resting_hr'].append(rhr)
    
    # Write to CSV
    output_file = 'vitality_data.csv'
    print(f"\nWriting to {output_file}...")
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['date', 'sleep_hours', 'steps', 'hrv_ms', 'resting_hr'])
        
        for date in sorted(daily_data.keys()):
            data = daily_data[date]
            sleep_hrs = round(data['sleep'], 1) if data['sleep'] > 0 else ''
            steps = int(data['steps']) if data['steps'] > 0 else ''
            hrv = round(sum(data['hrv']) / len(data['hrv']), 1) if data['hrv'] else ''
            rhr = round(sum(data['resting_hr']) / len(data['resting_hr']), 1) if data['resting_hr'] else ''
            
            # Only write rows with at least some data
            if sleep_hrs or steps:
                writer.writerow([date, sleep_hrs, steps, hrv, rhr])
    
    print(f"✅ Done! Created {output_file}")
    print("\nTo use in Miya:")
    print("1. Open the app")
    print("2. Tap the gear icon (⚙️) in top-right")
    print("3. Select 'Import Vitality Data'")
    print(f"4. Upload {output_file}")

if __name__ == '__main__':
    main()

