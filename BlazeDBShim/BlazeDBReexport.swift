//
//  BlazeDBReexport.swift
//  BlazeDB
//
//  Re-export file for umbrella BlazeDB target.
//  This allows downstream packages to depend on "BlazeDB" product
//  while the implementation lives in BlazeDBCore.
//
//  Note: BlazeDBDistributed remains disabled until Swift 6 compliant.
//

#if SWIFT_PACKAGE
@_exported import BlazeDBCore
// @_exported import BlazeDBDistributed  // Uncomment when distributed is Swift 6 compliant
#endif
