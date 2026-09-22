# Native UI test ledger

September 22, 2026. Actual XCTest case outcomes, including historical failed attempts.
Use the accompanying fix report to identify superseding passes and coverage limits.
“Passed” means that case’s assertions passed; it is not visual approval of every attachment.
Probe-only runs are omitted. Bundles are local under `dist/large-text-ui/`.

| Result bundle | Simulator | Test case | XCTest result |
|---|---|---|---|
| `ipad13-final` | iPad Pro 13-inch (M5) | `testIPadNarrowWindow()` | Passed |
| `ipad13-final` | iPad Pro 13-inch (M5) | `testPlayerMenusAndStoryCards()` | Failed |
| `ipad13-final` | iPad Pro 13-inch (M5) | `testSelectorsAndDetailSheets()` | Passed |
| `ipad13-final` | iPad Pro 13-inch (M5) | `testTextClippingAudit()` | Failed |
| `ipad13-finish` | iPad Pro 13-inch (M5) | `testIPadNarrowWindow()` | Passed |
| `ipad13-finish` | iPad Pro 13-inch (M5) | `testOnboardingTextSizesAndLandscape()` | Failed |
| `ipad13-finish` | iPad Pro 13-inch (M5) | `testPlayerMenusAndStoryCards()` | Passed |
| `ipad13-finish` | iPad Pro 13-inch (M5) | `testSettingsMenus()` | Passed |
| `ipad13-narrow-final` | iPad Pro 13-inch (M5) | `testIPadNarrowWindow()` | Passed |
| `ipad13-onboarding` | iPad Pro 13-inch (M5) | `testOnboardingTextSizesAndLandscape()` | Passed |
| `ipad13-review` | iPad Pro 13-inch (M5) | `testIPadNarrowWindow()` | Failed |
| `ipad13-review` | iPad Pro 13-inch (M5) | `testPlayerMenusAndStoryCards()` | Failed |
| `ipad13-review` | iPad Pro 13-inch (M5) | `testSettingsMenus()` | Failed |
| `ipad13-review` | iPad Pro 13-inch (M5) | `testTextClippingAudit()` | Passed |
| `ipad13-sections` | iPad Pro 13-inch (M5) | `testAllSectionsAccessibility5()` | Passed |
| `ipad13-sections` | iPad Pro 13-inch (M5) | `testAllSectionsDefault()` | Passed |
| `ipad13-window-control` | iPad Pro 13-inch (M5) | `testIPadWindowControlProbe()` | Passed |
| `ipad13-window-control` | iPad Pro 13-inch (M5) | `testPlayerMenusAndStoryCards()` | Failed |
| `ipad13-window-control` | iPad Pro 13-inch (M5) | `testTextClippingAudit()` | Failed |
| `iphone17-coverage` | iPhone 17 | `testCareerScopeSortingAndReturn()` | Passed |
| `iphone17-coverage` | iPhone 17 | `testOnboardingTextSizesAndLandscape()` | Failed |
| `iphone17-default-final` | iPhone 17 | `testAllSectionsDefault()` | Passed |
| `iphone17-live-final` | iPhone 17 | `testLiveTextSizeRetainsState()` | Passed |
| `iphone17-onboarding-final` | iPhone 17 | `testOnboardingTextSizesAndLandscape()` | Passed |
| `iphone17-onboarding-final` | iPhone 17 | `testPlayerMenusAndStoryCards()` | Passed |
| `iphone17-sections` | iPhone 17 | `testAllSectionsAccessibility5()` | Passed |
| `iphone17-sections` | iPhone 17 | `testAllSectionsDefault()` | Failed |
| `mini-career-fix` | iPad mini (A17 Pro) | `testCareerBattingRecordsAndTotals()` | Passed |
| `mini-career-fix` | iPad mini (A17 Pro) | `testCareerPitchingRecordsAndTotals()` | Passed |
| `mini-core` | iPad mini (A17 Pro) | `testCareerBattingRecordsAndTotals()` | Failed |
| `mini-core` | iPad mini (A17 Pro) | `testCareerPitchingRecordsAndTotals()` | Passed |
| `mini-core` | iPad mini (A17 Pro) | `testHomeRunChaseProjection()` | Passed |
| `mini-core` | iPad mini (A17 Pro) | `testRecapScrollingAndPlayerNavigation()` | Passed |
| `mini-core` | iPad mini (A17 Pro) | `testSearchKeyboardRotationAndBackground()` | Passed |
| `mini-finish` | iPad mini (A17 Pro) | `testCareerScopeSortingAndReturn()` | Passed |
| `mini-finish` | iPad mini (A17 Pro) | `testOnboardingTextSizesAndLandscape()` | Passed |
| `mini-finish` | iPad mini (A17 Pro) | `testPlayerMenusAndStoryCards()` | Passed |
| `mini-finish` | iPad mini (A17 Pro) | `testTextClippingAudit()` | Passed |
| `mini-sections-final` | iPad mini (A17 Pro) | `testAllSectionsAccessibility5()` | Passed |
| `mini-sections-final` | iPad mini (A17 Pro) | `testAllSectionsDefault()` | Passed |
| `promax-core` | HubBall Audit iPhone 16 Pro Max | `testCareerBattingRecordsAndTotals()` | Failed |
| `promax-core` | HubBall Audit iPhone 16 Pro Max | `testCareerPitchingRecordsAndTotals()` | Passed |
| `promax-core` | HubBall Audit iPhone 16 Pro Max | `testHomeRunChaseProjection()` | Passed |
| `promax-core` | HubBall Audit iPhone 16 Pro Max | `testRecapScrollingAndPlayerNavigation()` | Passed |
| `promax-core` | HubBall Audit iPhone 16 Pro Max | `testSearchKeyboardRotationAndBackground()` | Passed |
| `promax-final` | HubBall Audit iPhone 16 Pro Max | `testCareerBattingRecordsAndTotals()` | Passed |
| `promax-final` | HubBall Audit iPhone 16 Pro Max | `testCareerPitchingRecordsAndTotals()` | Passed |
| `promax-final` | HubBall Audit iPhone 16 Pro Max | `testSelectorsAndDetailSheets()` | Failed |
| `promax-final` | HubBall Audit iPhone 16 Pro Max | `testTextClippingAudit()` | Failed |
| `promax-finish` | HubBall Audit iPhone 16 Pro Max | `testAllSectionsAccessibility5()` | Passed |
| `promax-finish` | HubBall Audit iPhone 16 Pro Max | `testAllSectionsDefault()` | Passed |
| `promax-finish` | HubBall Audit iPhone 16 Pro Max | `testCareerScopeSortingAndReturn()` | Passed |
| `promax-finish` | HubBall Audit iPhone 16 Pro Max | `testOnboardingTextSizesAndLandscape()` | Failed |
| `promax-finish` | HubBall Audit iPhone 16 Pro Max | `testPlayerMenusAndStoryCards()` | Passed |
| `promax-finish` | HubBall Audit iPhone 16 Pro Max | `testSelectorsAndDetailSheets()` | Passed |
| `promax-finish` | HubBall Audit iPhone 16 Pro Max | `testSettingsMenus()` | Passed |
| `promax-live-size` | HubBall Audit iPhone 16 Pro Max | `testLiveTextSizeRetainsState()` | Skipped |
| `promax-live-size2` | HubBall Audit iPhone 16 Pro Max | `testLiveTextSizeRetainsState()` | Passed |
| `promax-menu-audit` | HubBall Audit iPhone 16 Pro Max | `testPlayerMenusAndStoryCards()` | Failed |
| `promax-menu-audit` | HubBall Audit iPhone 16 Pro Max | `testTextClippingAudit()` | Failed |
| `promax-native-picker` | HubBall Audit iPhone 16 Pro Max | `testPlayerMenusAndStoryCards()` | Failed |
| `promax-native-picker` | HubBall Audit iPhone 16 Pro Max | `testTextClippingAudit()` | Passed |
| `promax-onboarding-final` | HubBall Audit iPhone 16 Pro Max | `testOnboardingTextSizesAndLandscape()` | Passed |
| `promax-review` | HubBall Audit iPhone 16 Pro Max | `testHomeRunChaseProjection()` | Passed |
| `promax-review` | HubBall Audit iPhone 16 Pro Max | `testIntermediateTextSizes()` | Passed |
| `promax-review` | HubBall Audit iPhone 16 Pro Max | `testPlayerMenusAndStoryCards()` | Failed |
| `promax-review` | HubBall Audit iPhone 16 Pro Max | `testSelectorsAndDetailSheets()` | Failed |
| `promax-review` | HubBall Audit iPhone 16 Pro Max | `testSettingsMenus()` | Failed |
| `promax-review` | HubBall Audit iPhone 16 Pro Max | `testTextClippingAudit()` | Passed |
| `se-coverage` | HubBall Audit iPhone SE | `testCareerScopeSortingAndReturn()` | Passed |
| `se-coverage` | HubBall Audit iPhone SE | `testOnboardingTextSizesAndLandscape()` | Failed |
| `se-final` | HubBall Audit iPhone SE | `testAllSectionsDefault()` | Passed |
| `se-final` | HubBall Audit iPhone SE | `testBrewersStoryControlsAndSources()` | Passed |
| `se-final` | HubBall Audit iPhone SE | `testCareerBattingRecordsAndTotals()` | Passed |
| `se-final` | HubBall Audit iPhone SE | `testCareerPitchingRecordsAndTotals()` | Passed |
| `se-final` | HubBall Audit iPhone SE | `testPlayerMenusAndStoryCards()` | Failed |
| `se-final` | HubBall Audit iPhone SE | `testSelectorsAndDetailSheets()` | Passed |
| `se-final` | HubBall Audit iPhone SE | `testTextClippingAudit()` | Failed |
| `se-full2` | HubBall Audit iPhone SE | `testAllSectionsAccessibility5()` | Passed |
| `se-full2` | HubBall Audit iPhone SE | `testAllSectionsDefault()` | Failed |
| `se-full2` | HubBall Audit iPhone SE | `testBostonStoryPlayback()` | Passed |
| `se-full2` | HubBall Audit iPhone SE | `testBrewersStoryControlsAndSources()` | Passed |
| `se-full2` | HubBall Audit iPhone SE | `testCareerBattingRecordsAndTotals()` | Failed |
| `se-full2` | HubBall Audit iPhone SE | `testCareerPitchingRecordsAndTotals()` | Failed |
| `se-full2` | HubBall Audit iPhone SE | `testHomeRunChaseProjection()` | Passed |
| `se-full2` | HubBall Audit iPhone SE | `testRecapScrollingAndPlayerNavigation()` | Passed |
| `se-full2` | HubBall Audit iPhone SE | `testSearchKeyboardRotationAndBackground()` | Passed |
| `se-full2` | HubBall Audit iPhone SE | `testTextClippingAudit()` | Failed |
| `se-initial3` | HubBall Audit iPhone SE | `testCareerBattingRecordsAndTotals()` | Passed |
| `se-initial3` | HubBall Audit iPhone SE | `testCareerPitchingRecordsAndTotals()` | Passed |
| `se-initial3` | HubBall Audit iPhone SE | `testRecapScrollingAndPlayerNavigation()` | Passed |
| `se-onboarding-final` | HubBall Audit iPhone SE | `testOnboardingTextSizesAndLandscape()` | Passed |
| `se-onboarding-visible` | HubBall Audit iPhone SE | `testOnboardingTextSizesAndLandscape()` | Passed |
| `se-onboarding` | HubBall Audit iPhone SE | `testOnboardingTextSizesAndLandscape()` | Failed |
| `se-review` | HubBall Audit iPhone SE | `testIntermediateTextSizes()` | Passed |
| `se-review` | HubBall Audit iPhone SE | `testPlayerMenusAndStoryCards()` | Passed |
| `se-review` | HubBall Audit iPhone SE | `testSettingsMenus()` | Passed |
| `se-review` | HubBall Audit iPhone SE | `testTextClippingAudit()` | Passed |
| `se-sections` | HubBall Audit iPhone SE | `testAllSectionsAccessibility5()` | Failed |
| `se-sections` | HubBall Audit iPhone SE | `testHomeRunChaseProjection()` | Passed |
| `se-sections` | HubBall Audit iPhone SE | `testSearchKeyboardRotationAndBackground()` | Passed |
