#!/usr/bin/env python3
"""
BlazeDB Performance Tracking Script
Extracts metrics from XCTest results and tracks trends over time
"""

import json
import sys
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

class PerformanceTracker:
    def __init__(self, baseline_file: str = "baselines/performance_baseline.json"):
        self.baseline_file = Path(baseline_file)
        self.baseline = self._load_baseline()
        self.current_metrics = {}
        self.regressions = []
        
    def _load_baseline(self) -> Dict:
        """Load performance baseline from JSON file"""
        if self.baseline_file.exists():
            with open(self.baseline_file, 'r') as f:
                return json.load(f)
        return {}
    
    def parse_xcresult(self, xcresult_path: str) -> Dict[str, float]:
        """Parse XCTest .xcresult file and extract performance metrics"""
        print(f"📊 Parsing {xcresult_path}...")
        
        try:
            # Use xcresulttool to extract JSON
            result = subprocess.run(
                ['xcrun', 'xcresulttool', 'get', '--path', xcresult_path, '--format', 'json'],
                capture_output=True,
                text=True,
                check=True
            )
            
            data = json.loads(result.stdout)
            metrics = self._extract_metrics(data)
            
            print(f"  ✅ Extracted {len(metrics)} performance metrics")
            return metrics
            
        except subprocess.CalledProcessError as e:
            print(f"  ❌ Error parsing xcresult: {e}")
            return {}
    
    def _extract_metrics(self, data: Dict) -> Dict[str, float]:
        """Extract performance metrics from parsed xcresult JSON"""
        metrics = {}
        
        # Navigate through XCTest result structure
        # This is a simplified parser - actual implementation would be more robust
        if 'actions' in data:
            for action in data['actions'].get('_values', []):
                if 'actionResult' in action:
                    tests = action['actionResult'].get('testsRef', {}).get('_values', [])
                    for test in tests:
                        self._parse_test_metrics(test, metrics)
        
        return metrics
    
    def _parse_test_metrics(self, test: Dict, metrics: Dict[str, float]):
        """Recursively parse test hierarchy to find performance metrics"""
        test_name = test.get('name', {}).get('_value', '')
        
        # Check if this test has performance metrics
        if 'performanceMetrics' in test:
            for metric in test['performanceMetrics'].get('_values', []):
                metric_name = f"{test_name}.{metric.get('displayName', {}).get('_value', '')}"
                value = metric.get('measurements', {}).get('_values', [{}])[0].get('value', {}).get('_value', 0)
                metrics[metric_name] = float(value)
        
        # Recurse into subtests
        if 'subtests' in test:
            for subtest in test['subtests'].get('_values', []):
                self._parse_test_metrics(subtest, metrics)
    
    def compare_to_baseline(self, current: Dict[str, float], threshold: float = 0.10):
        """Compare current metrics to baseline and find regressions"""
        print("\n📈 Comparing to baseline...")
        
        for test_name, current_value in current.items():
            baseline_value = self.baseline.get(test_name)
            
            if baseline_value is None:
                print(f"  ℹ️  New test: {test_name} = {current_value:.6f}s")
                continue
            
            # Calculate regression percentage
            regression = ((current_value - baseline_value) / baseline_value) * 100
            
            if regression > threshold * 100:  # More than threshold% slower
                self.regressions.append({
                    'test': test_name,
                    'baseline': baseline_value,
                    'current': current_value,
                    'regression_pct': regression
                })
                print(f"  ⚠️  REGRESSION: {test_name}")
                print(f"      Baseline: {baseline_value:.6f}s")
                print(f"      Current:  {current_value:.6f}s")
                print(f"      Slower by: {regression:.1f}%")
            elif regression < -threshold * 100:  # More than threshold% faster
                print(f"  ✅ IMPROVEMENT: {test_name}")
                print(f"      Baseline: {baseline_value:.6f}s")
                print(f"      Current:  {current_value:.6f}s")
                print(f"      Faster by: {abs(regression):.1f}%")
    
    def save_current_as_baseline(self, metrics: Dict[str, float]):
        """Save current metrics as new baseline"""
        self.baseline_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(self.baseline_file, 'w') as f:
            json.dump(metrics, f, indent=2)
        
        print(f"\n💾 Saved {len(metrics)} metrics as new baseline")
    
    def generate_report(self) -> bool:
        """Generate final report and return success status"""
        print("\n" + "=" * 60)
        print("📊 PERFORMANCE REPORT")
        print("=" * 60)
        
        if not self.regressions:
            print("✅ No performance regressions detected!")
            print("   All metrics within acceptable range (±10%)")
            return True
        else:
            print(f"⚠️  {len(self.regressions)} PERFORMANCE REGRESSIONS DETECTED:")
            print("")
            
            for reg in sorted(self.regressions, key=lambda x: x['regression_pct'], reverse=True):
                print(f"  • {reg['test']}")
                print(f"    Baseline: {reg['baseline']:.6f}s")
                print(f"    Current:  {reg['current']:.6f}s")
                print(f"    Regression: {reg['regression_pct']:.1f}%")
                print("")
            
            print("⚠️  RECOMMENDATION: Investigate these regressions before merging!")
            return False

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Track BlazeDB performance metrics')
    parser.add_argument('xcresult', nargs='?', help='Path to .xcresult file')
    parser.add_argument('--baseline', default='baselines/performance_baseline.json',
                       help='Path to baseline file')
    parser.add_argument('--save-baseline', action='store_true',
                       help='Save current run as new baseline')
    parser.add_argument('--threshold', type=float, default=0.10,
                       help='Regression threshold (default: 0.10 = 10%%)')
    
    args = parser.parse_args()
    
    # Find latest .xcresult if not specified
    if not args.xcresult:
        build_dir = Path('.build/debug')
        xcresults = list(build_dir.glob('*.xcresult'))
        if xcresults:
            args.xcresult = str(sorted(xcresults, key=lambda p: p.stat().st_mtime)[-1])
        else:
            print("❌ No .xcresult files found in .build/debug/")
            print("   Run: swift test --enable-code-coverage")
            return 1
    
    print(f"🔍 Analyzing: {args.xcresult}")
    print(f"📁 Baseline: {args.baseline}")
    print("")
    
    tracker = PerformanceTracker(baseline_file=args.baseline)
    current = tracker.parse_xcresult(args.xcresult)
    
    if not current:
        print("⚠️  No performance metrics found in test results")
        print("   Make sure your tests use measure {} blocks")
        return 0
    
    # Compare to baseline
    tracker.compare_to_baseline(current, threshold=args.threshold)
    
    # Save as new baseline if requested
    if args.save_baseline:
        tracker.save_current_as_baseline(current)
    
    # Generate final report
    success = tracker.generate_report()
    
    return 0 if success else 1

if __name__ == '__main__':
    sys.exit(main())

