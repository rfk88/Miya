//
//  WeeklyVitalityScheduler.swift
//  Miya Health
//
//  Calendar-based scheduler for weekly family vitality refresh (Sundays only)
//

import Foundation

class WeeklyVitalityScheduler {
    static let shared = WeeklyVitalityScheduler()
    
    private let userDefaults = UserDefaults.standard
    private let lastRefreshKey = "miya.lastFamilyVitalityRefresh"
    
    private init() {}
    
    /// Check if family vitality should be refreshed (only on Sundays, once per week)
    func shouldRefreshFamilyVitality() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        
        // Check if today is Sunday (weekday 1 in Calendar)
        let weekday = calendar.component(.weekday, from: now)
        guard weekday == 1 else {
            #if DEBUG
            print("📅 WeeklyVitalityScheduler: Not Sunday (weekday=\(weekday)), skipping refresh")
            #endif
            return false
        }
        
        // Check if we already refreshed this Sunday
        guard let lastRefreshDate = lastRefreshDate else {
            #if DEBUG
            print("📅 WeeklyVitalityScheduler: No previous refresh, allowing refresh")
            #endif
            return true
        }
        
        // Compare week-of-year to see if we've refreshed this week
        let nowComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let lastRefreshComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lastRefreshDate)
        
        let shouldRefresh = nowComponents.yearForWeekOfYear != lastRefreshComponents.yearForWeekOfYear ||
                           nowComponents.weekOfYear != lastRefreshComponents.weekOfYear
        
        #if DEBUG
        if shouldRefresh {
            print("📅 WeeklyVitalityScheduler: New week detected, allowing refresh")
        } else {
            print("📅 WeeklyVitalityScheduler: Already refreshed this week, skipping")
        }
        #endif
        
        return shouldRefresh
    }
    
    /// Mark that family vitality was refreshed (call after successful refresh)
    func markRefreshed() {
        userDefaults.set(Date(), forKey: lastRefreshKey)
        #if DEBUG
        print("📅 WeeklyVitalityScheduler: Marked refresh at \(Date())")
        #endif
    }
    
    /// Force a refresh (for debug/support scenarios)
    func forceRefresh() {
        userDefaults.removeObject(forKey: lastRefreshKey)
        #if DEBUG
        print("📅 WeeklyVitalityScheduler: Force refresh enabled (cleared last refresh date)")
        #endif
    }
    
    /// Get the last refresh date (for debugging/UI display)
    var lastRefreshDate: Date? {
        return userDefaults.object(forKey: lastRefreshKey) as? Date
    }
    
    /// Check if a force refresh is needed (for first-time users or mid-week launches)
    /// Returns true if user has never refreshed OR if it's been >7 days since last refresh
    func needsInitialRefresh() -> Bool {
        guard let lastRefresh = lastRefreshDate else {
            return true // Never refreshed
        }
        
        let daysSinceRefresh = Calendar.current.dateComponents([.day], from: lastRefresh, to: Date()).day ?? 0
        return daysSinceRefresh >= 7
    }
}
