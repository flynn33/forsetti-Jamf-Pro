# Public Product Release Checklist

Status: **Blocked**

Forsetti Jamf Pro is not ready for public product distribution. Complete and verify every required gate below before making an application build publicly available.

## Evaluation enforcement

- [ ] Start one 30-consecutive-day Evaluation Period on the first execution of any evaluation build.
- [ ] Persist the start date outside ordinary app preferences so reinstalling or clearing preferences does not restart the period.
- [ ] Detect material clock rollback and define a safe, supportable recovery path for false positives.
- [ ] Show the trial duration, expiration date, affected functionality, and purchase requirement before the Evaluation Period starts.
- [ ] Lock application functionality when the Evaluation Period expires while preserving access to purchase, license, support, and data-export information.
- [ ] Prevent a different build, repository revision, or local modification from silently starting a new Evaluation Period.
- [ ] Add automated tests for first run, active evaluation, expiration, reinstall, clock change, offline operation, and corrupted license state.

## Purchase and entitlement

- [ ] Define the Apple App Store product and entitlement model.
- [ ] Verify a valid purchase before unlocking continued application use.
- [ ] Support purchase restoration and device changes.
- [ ] Define offline behavior and a bounded entitlement-verification grace period.
- [ ] Keep source-built and locally modified versions outside the App Store purchase grant unless a separate written license authorizes them.
- [ ] If the trial is offered inside a non-subscription App Store build, implement the current App Store-approved trial mechanism and required pre-trial disclosures.
- [ ] Confirm the final trial and purchase flow against the current App Store Review Guidelines before submission.

## Legal and release presentation

- [ ] Present the proprietary license before evaluation begins and make it available from the app.
- [ ] Display the copyright notice and third-party notices in the distributed application.
- [ ] Ensure release notes, App Store metadata, pricing, trial disclosures, and in-app language describe the same terms.
- [ ] Confirm ownership and license compatibility for all source, dependencies, icons, and bundled assets.
- [ ] Obtain legal review of the custom license, evaluation flow, purchase terms, and copyright-owner identity.
- [ ] Complete signed archive, notarization where applicable, App Store review, and release validation.

Do not mark this checklist complete based only on the written policy. The enforcement, entitlement, disclosure, and recovery paths must be implemented and tested in the shipping build.
