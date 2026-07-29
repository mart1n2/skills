<!--
EXTERNAL REPORT TEMPLATE - AUTHORING RULES

Purpose
- Use this only when the user explicitly requests an external, client-facing,
  public, or professional smart contract security report. It is not the default
  audit output; `audit-report.md` is the default internal reference report.
- Generating the report does not authorize client delivery or public release;
  publication and external distribution require explicit approval.
- Build scope, methodology, coverage, limitations, findings, and remediation
  content from the canonical workspace artifacts (`scope.md`, `target-lock.md`,
  `findings.md`, `coverage.md`) and retained workspace evidence.
- Include an item in the Findings sections only when it is a human-accepted
  finding in `findings.md`.
- Do not use it as the candidate ledger, evidence store, or triage record.
- Retain all internal audit-workspace data, including
  needed tmp data, after generating or publishing this report.
- Store the canonical editable report source under the audit workspace's
  `reports/` directory. Treat client-delivery and public files as export copies.

Publication modes
- Before explicit delivery/publication approval, use CLIENT-CONFIDENTIAL and
  DRAFT. Do not mark a report PUBLIC merely because this template is external-format.
- PUBLIC: remove exploit-enabling detail while an issue is embargoed or remains
  exploitable. Preserve the finding's existence, original severity, status, and
  high-level impact unless the disclosure agreement requires stronger redaction.
- CLIENT-CONFIDENTIAL: include enough technical detail for the client to reproduce
  and remediate the issue, subject to the engagement's handling rules.

Placeholder rules
- Replace every {{UPPER_SNAKE_CASE}} placeholder before release.
- Delete optional sections that do not apply; do not leave empty headings.
- Use YYYY-MM-DD dates, full commit hashes, and checksummed addresses where relevant.
- Do not write "TBD". Use one of:
  - NOT ASSESSED - {{REASON}}
  - UNKNOWN - {{REASON}}
  - NOT APPLICABLE - {{REASON}}
- Delete all authoring comments, including this block, from the released report.

Truth and redaction rules
- Bind every conclusion to the exact audited baseline and stated assessment period.
- GitHub repository and commit fields apply only when repository source is part of
  the baseline. For a chain-only target, delete those optional rows or mark them
  not applicable; never fabricate a commit. Identify the target with its native
  deployment ID, code/package digest, and immutable state anchor. Resolve `latest`
  once; for EVM record both block number and block hash, not either one alone.
- Report only accepted findings. Do not expose internal candidates or rejected leads.
- Keep original severity separate from deployment exposure and remediation status.
- When projecting the workspace deployment field, map `confirmed exploitable` to
  Confirmed Exposed, `conditionally exposed` to Conditionally Exposed,
  `not exposed at pinned state` to Not Exposed in Reviewed Deployment,
  `not deployed` to Not Deployed, and `unknown` to Unknown / Not Assessed. Map
  `plausibly exposed` to Unknown / Not Assessed with the unresolved question;
  never upgrade uncertainty into Conditionally Exposed.
- "FIXED - VERIFIED" requires review of the exact remediation revision. A fix review
  is not a full re-audit unless the report explicitly says otherwise.
- Do not disclose local paths, private repository links, raw exploit artifacts,
  secrets, private communications, internal agent/runtime details, or internal IDs.
- If a technical detail is redacted, say what category was withheld and why.

Release process
1. Complete the internal workspace artifacts and closure gate.
2. Project accepted findings and recipient-appropriate, disclosure-controlled
   evidence into this report.
3. Reconcile every count and status against `findings.md`.
4. Obtain technical, client, disclosure, and publication approval as applicable.
5. Run the release checklist at the end of this file.
-->

# {{PROJECT_NAME}}

## Smart Contract Security Assessment

**Report classification:** {{PUBLIC_OR_CLIENT_CONFIDENTIAL}}<br>
**Report status:** {{DRAFT_OR_FINAL}}<br>
**Report version:** {{REPORT_VERSION}}<br>
**Publication date:** {{PUBLICATION_DATE_OR_NOT_APPLICABLE_WITH_REASON}}

Prepared for **{{CLIENT_LEGAL_OR_PUBLIC_NAME}}**<br>
Prepared by **{{ASSESSOR_NAME}}**

{{OPTIONAL_PROJECT_LOGO_OR_COVER_ART}}

<!-- PAGE BREAK -->

## Report Control

### Document Metadata

| Field | Value |
|---|---|
| Report ID | {{REPORT_ID}} |
| Project | {{PROJECT_NAME}} |
| Assessment type | {{DESIGN_REVIEW_SOURCE_REVIEW_DEPLOYMENT_REVIEW_FIX_REVIEW_OR_COMBINATION}} |
| Client | {{CLIENT_LEGAL_OR_PUBLIC_NAME}} |
| Assessor | {{ASSESSOR_NAME}} |
| Assessment period | {{START_DATE}} to {{END_DATE}} |
| Report date | {{YYYY_MM_DD}} |
| Audited baseline | {{IMMUTABLE_SOURCE_BUILD_PACKAGE_PROGRAM_BYTECODE_OR_DEPLOYMENT_BASELINES}} |
| Remediation baseline | {{FULL_COMMIT_PACKAGE_DIGEST_OR_NOT_APPLICABLE_WITH_REASON}} |
| Networks | {{NETWORKS}} |
| Classification | {{PUBLIC_OR_CLIENT_CONFIDENTIAL}} |
| Canonical report location | {{CANONICAL_URL_OR_NOT_APPLICABLE_WITH_REASON}} |
| Security contact | {{SECURITY_CONTACT_OR_SECURITY_TXT_URL}} |

### Revision History

| Version | Date | Status | Baseline | Description | Approved by |
|---|---|---|---|---|---|
| {{VERSION}} | {{YYYY_MM_DD}} | {{DRAFT_FINAL_OR_SUPERSEDED}} | {{IMMUTABLE_BASELINE_REVISION_OR_DIGEST}} | {{INITIAL_ASSESSMENT_FIX_REVIEW_OR_CORRECTION}} | {{APPROVER}} |

### Distribution and Reliance

This report is intended for {{INTENDED_AUDIENCE}}. Its conclusions apply only to
the scope, versions, configurations, and assumptions stated in this report. Any
other use or reliance is subject to the engagement terms and the limitations in
the final section.

<!--
For a public report, state whether it may be redistributed unchanged and identify
the canonical location. For a confidential report, list authorized recipients or
refer to the governing agreement without reproducing sensitive terms.
-->

<!-- PAGE BREAK -->

## Table of Contents

<!-- Generate this table from the final headings. Do not maintain it manually. -->

{{GENERATED_TABLE_OF_CONTENTS}}

<!-- PAGE BREAK -->

## 1. Executive Summary

### 1.1 Assessment Objective

{{ASSESSOR_NAME}} assessed {{PROJECT_NAME}} to evaluate whether the in-scope
implementation preserves its stated security properties under the threat model
and assumptions documented in this report. The review covered the exact baseline
identified in [Section 3](#3-assessment-scope).

### 1.2 Overall Conclusion

**Assessment conclusion:** {{NO_MATERIAL_FINDINGS_IDENTIFIED_FINDINGS_PRESENT_OR_INCOMPLETE}}

{{BOUNDED_EXECUTIVE_CONCLUSION}}

<!--
Choose and adapt one evidence-bounded formulation:

No material findings identified:
"No material security findings were identified within the reviewed scope and
baseline during the assessment period. This conclusion does not cover excluded
components, later changes, or defects not discovered by this time-boxed review."

Findings present:
"The assessment identified material security findings in the reviewed baseline.
The current residual risk depends on the remediation statuses and deployment
exposure stated below."

Incomplete:
"The assessment cannot support an unqualified conclusion because the material
coverage limitations or unresolved assumptions listed below prevented sufficient
evaluation of one or more security-critical properties."

Avoid subjective claims such as "high level of security," "fully secure," or
"safe to deploy."
-->

### 1.3 Results at a Glance

#### Findings by Original Severity

| Severity | Critical | High | Medium | Low | Informational | Total |
|---|---:|---:|---:|---:|---:|---:|
| Count | {{N}} | {{N}} | {{N}} | {{N}} | {{N}} | {{N}} |

#### Findings by Current Status

| Status | Count |
|---|---:|
| Open | {{N}} |
| Fixed - Verified | {{N}} |
| Partially Fixed | {{N}} |
| Acknowledged | {{N}} |
| Risk Accepted | {{N}} |
| Not Yet Retested | {{N}} |
| Total | {{N}} |

Only **Fixed - Verified** is treated as resolved in this report. Acknowledged,
Risk Accepted, Partially Fixed, Open, and Not Yet Retested findings remain in the
residual-risk view.

### 1.4 Material Unresolved Risk

{{SUMMARY_OF_OPEN_PARTIAL_ACCEPTED_OR_UNRETESTED_MATERIAL_FINDINGS_OR_NONE}}

### 1.5 Material Coverage Limitations

{{SUMMARY_OF_LIMITATIONS_THAT_COULD_CHANGE_THE_CONCLUSION_OR_NONE}}

### 1.6 Remediation Review Summary

{{WHETHER_A_FIX_REVIEW_WAS_PERFORMED_EXACT_REMEDIATION_BASELINE_AND_BOUNDED_RESULT}}

<!-- PAGE BREAK -->

## 2. Findings Overview

| ID | Finding | Original Severity | Current Status | Deployment Exposure | Affected Baseline |
|---|---|---|---|---|---|
| {{F_01}} | {{SHORT_TITLE}} | {{CRITICAL_HIGH_MEDIUM_LOW_OR_INFORMATIONAL}} | {{STATUS}} | {{EXPOSURE}} | {{IMMUTABLE_REVISION_DIGEST_OR_DEPLOYMENT_ID}} |

### 2.1 Interpretation

- **Original Severity** records the technical risk in the affected audited
  baseline. It does not decrease when a finding is remediated.
- **Deployment Exposure** states whether the vulnerable condition was shown to
  apply to a reviewed deployment or remains source/configuration dependent.
- **Current Status** records the remediation outcome as of the report version.
- A finding marked **Fixed - Verified** was rechecked against the exact revision
  listed for that finding. This does not imply that unrelated changes were
  comprehensively re-audited.

### 2.2 Non-Finding Considerations

{{COUNT_OR_NONE}} non-finding considerations are listed in
[Section 9](#9-system-considerations). They are separated from security findings
and are not included in severity counts.

<!-- PAGE BREAK -->

## 3. Assessment Scope

### 3.1 In-Scope Baseline

| Field | Value |
|---|---|
| Repository or source location | {{PUBLIC_REPOSITORY_URL_OR_CLIENT_SOURCE_REFERENCE}} |
| Source revision(s) | {{IMMUTABLE_REVISIONS_DIGESTS_OR_NOT_APPLICABLE_WITH_REASON}} |
| Release or tag | {{TAG_OR_NOT_APPLICABLE_WITH_REASON}} |
| Package/program/module digest | {{DIGEST_OR_NOT_APPLICABLE_WITH_REASON}} |
| Compiler and version | {{COMPILER_AND_EXACT_VERSION}} |
| Framework and version | {{FRAMEWORK_AND_EXACT_VERSION}} |
| Build profile | {{BUILD_FLAGS_FEATURES_OPTIMIZER_SETTINGS_AND_LOCKFILE}} |
| Dependency lock | {{LOCKFILE_DIGEST_OR_NOT_APPLICABLE_WITH_REASON}} |
| Test command | {{REPRODUCIBLE_TEST_COMMAND_OR_NOT_ASSESSED_WITH_REASON}} |
| Build command | {{REPRODUCIBLE_BUILD_COMMAND_OR_NOT_ASSESSED_WITH_REASON}} |

<!--
Repository rows are optional. For a chain-only engagement, delete them or state
NOT APPLICABLE with the reason. Do not leave them blank and do not substitute an
observation block for a nonexistent source revision; record the chain anchor in
Reviewed Deployments instead.
-->

### 3.2 In-Scope Components

| Component or Path | Role | Language | Notes |
|---|---|---|---|
| `{{SOURCE_PATH_OR_COMPONENT}}` | {{SECURITY_RELEVANT_ROLE}} | {{LANGUAGE}} | {{INCLUSION_NOTES}} |

<!--
List exact files where practical. For large generated or vendored trees, identify
the pinned manifest/digest and the precise inclusion rule. Do not use broad phrases
such as "all contracts" unless that claim is mechanically true and reproducible.
-->

### 3.3 Reviewed Deployments

| Network | Component | Address or Object ID | Code/Package Digest | Immutable State Anchor | Admin/Upgrade Authority | Binding Result |
|---|---|---|---|---|---|---|
| {{NETWORK}} | {{COMPONENT}} | `{{CHECKSUMMED_ADDRESS_OR_OBJECT_ID}}` | `{{DIGEST}}` | {{BLOCK_NUMBER_AND_HASH_SLOT_CHECKPOINT_OR_OBJECT_VERSION}} | {{AUTHORITY}} | {{MATCH_MISMATCH_UNKNOWN_OR_NOT_ASSESSED_WITH_REASON}} |

### 3.4 Source-to-Deployment Binding

{{HOW_THE_REVIEWED_SOURCE_BUILD_ARTIFACT_AND_DEPLOYED_CODE_WERE_OR_WERE_NOT_BOUND}}

<!--
State the actual procedure and result. Examples include reproducible build and
bytecode match, explorer-verified source comparison, package digest comparison,
program-data hash comparison, or an explicit statement that deployment binding
was not assessed. Do not imply deployed-state assurance from source review alone.
-->

### 3.5 Out of Scope

- {{EXCLUDED_COMPONENT_OR_ACTIVITY}} - {{WHY_EXCLUDED_AND_SECURITY_RELEVANCE}}

Common exclusions to consider only when true:

- Frontend, API, indexer, keeper, and other off-chain services
- Private-key generation, custody, signer operations, and governance processes
- Third-party contracts, bridges, oracles, tokens, and infrastructure
- Deployment scripts, migrations, and production configuration
- Economic behavior outside the documented assumptions and parameter ranges
- Changes made after the audited baseline

### 3.6 External Dependencies

| Dependency | Version/Address | Security Role | Assumption | Reviewed? |
|---|---|---|---|---|
| {{DEPENDENCY}} | {{VERSION_OR_ADDRESS}} | {{ROLE}} | {{ASSUMPTION}} | {{YES_PARTIAL_NO}} |

### 3.7 Prior Reviews and Known Issues

{{PRIOR_REPORTS_KNOWN_ISSUES_AND_WHETHER_THEY_WERE_IN_SCOPE_OR_NOT_PROVIDED}}

### 3.8 Assessment Timeline

| Date | Event | Baseline |
|---|---|---|
| {{YYYY_MM_DD}} | {{KICKOFF_SCOPE_CHANGE_INITIAL_DELIVERY_FIX_DELIVERY_RETEST_OR_FINAL_REPORT}} | {{FULL_COMMIT_DIGEST_OR_NOT_APPLICABLE}} |

<!-- PAGE BREAK -->

## 4. System Overview

### 4.1 Purpose and Security-Relevant Design

{{CONCISE_DESCRIPTION_OF_THE_PROTOCOL_AND_WHAT_THE_REVIEWED_COMPONENTS_CONTROL}}

### 4.2 Architecture

{{ARCHITECTURE_DIAGRAM_OR_LINK}}

<!--
Use a diagram when it materially clarifies assets, trust boundaries, privileged
roles, external dependencies, or state transitions. Label every external system
and mark which components were outside the audit scope.
-->

### 4.3 Assets and Value Flows

| Asset or Right | Entry Point | Custody/Accounting Location | Exit or Settlement Path | Primary Risk |
|---|---|---|---|---|
| {{ASSET_OR_CAPABILITY}} | {{ENTRY}} | {{LOCATION}} | {{EXIT}} | {{LOSS_CORRUPTION_FREEZE_OR_CONTROL_RISK}} |

### 4.4 Core Flows

#### {{FLOW_NAME}}

1. {{SECURITY_RELEVANT_STEP}}
2. {{SECURITY_RELEVANT_STEP}}
3. {{SECURITY_RELEVANT_STEP}}

**Required property:** {{INVARIANT_OR_POSTCONDITION}}

### 4.5 Upgrade and Administration Model

{{PROXY_PACKAGE_OR_PROGRAM_UPGRADE_MODEL_TIMELOCK_MULTISIG_PAUSE_AND_EMERGENCY_PATHS}}

### 4.6 Economic and Numerical Model

{{PRICING_ACCOUNTING_SOLVENCY_ROUNDING_OR_RATE_LIMIT_MODEL_AND_PARAMETER_BOUNDS}}

<!-- PAGE BREAK -->

## 5. Security Model and Trust Assumptions

### 5.1 Protected Assets and Security Properties

| ID | Asset or Property | Required Invariant | Failure Impact |
|---|---|---|---|
| {{INV_01}} | {{ASSET_OR_PROPERTY}} | {{PRECISE_SAFETY_OR_ECONOMIC_INVARIANT}} | {{IMPACT}} |

### 5.2 Threat Actors and Capabilities

| Actor | Assumed Capabilities | Explicitly Excluded Capabilities |
|---|---|---|
| {{UNPRIVILEGED_USER_BLOCK_BUILDER_COMPROMISED_ROLE_OR_OTHER}} | {{CAPABILITIES}} | {{EXCLUSIONS}} |

### 5.3 Privileged Roles

| Role | Security-Critical Powers | Controls | Residual Trust |
|---|---|---|---|
| {{ROLE}} | {{POWERS}} | {{MULTISIG_TIMELOCK_RATE_LIMIT_MONITORING_OR_OTHER}} | {{WHAT_USERS_MUST_TRUST}} |

### 5.4 Operational and Environmental Assumptions

- {{ASSUMPTION}} - {{CONSEQUENCE_IF_FALSE}}

### 5.5 External Trust Boundaries

| Boundary | Trusted Property | Failure Mode | Protocol Response |
|---|---|---|---|
| {{ORACLE_BRIDGE_TOKEN_SEQUENCER_VALIDATOR_KEEPER_OR_OTHER}} | {{PROPERTY}} | {{FAILURE}} | {{RESPONSE_OR_NONE}} |

### 5.6 Deployment-Specific Assumptions

{{INITIALIZATION_PARAMETERS_ROLE_ASSIGNMENTS_LIQUIDITY_STATE_GOVERNANCE_OR_OTHER_ASSUMPTIONS}}

<!-- PAGE BREAK -->

## 6. Methodology, Coverage, and Limitations

### 6.1 Review Approach

The assessment used methods selected for the target's design, implementation,
and available evidence. Methods are reported because they were actually used,
not because they appear on a standard checklist.

| Activity | Scope | Purpose | Result or Evidence Basis |
|---|---|---|---|
| {{ARCHITECTURE_AND_THREAT_MODEL_REVIEW}} | {{SCOPE}} | {{PURPOSE}} | {{RESULT}} |
| {{MANUAL_CODE_REVIEW}} | {{SCOPE}} | {{PURPOSE}} | {{RESULT}} |
| {{TESTING_FUZZING_SYMBOLIC_ANALYSIS_FORMAL_ANALYSIS_SIMULATION_REPLAY_TRACE_ANALYSIS_OR_OTHER}} | {{SCOPE}} | {{PURPOSE}} | {{RESULT}} |
| {{DEPENDENCY_BUILD_OR_DEPLOYMENT_VERIFICATION}} | {{SCOPE}} | {{PURPOSE}} | {{RESULT}} |

<!--
Do not constrain the assessor to a fixed discovery or validation technique. State
what was done and bind conclusions to sufficient, reproducible evidence. Delete
unused rows rather than claiming activities that were not performed.
-->

### 6.2 Security Coverage

| Security Area | Components/Flows Reviewed | Coverage Basis | Material Limitation |
|---|---|---|---|
| Access control and authorization | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |
| Asset accounting and conservation | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |
| State transitions and lifecycle | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |
| External calls and integrations | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |
| Upgradeability and initialization | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |
| Numerical and economic behavior | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |
| Chain-specific execution semantics | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |
| Availability and denial of service | {{SCOPE}} | {{METHOD_OR_EVIDENCE}} | {{NONE_OR_LIMITATION}} |

### 6.3 Standards Mapping

{{WHETHER_A_STANDARD_WAS_USED_AND_EXACT_VERSION_OR_NOT_APPLICABLE_WITH_REASON}}

<!--
Optional mappings can aid coverage communication but do not prove compliance.
- OWASP SCSVS/SCSTG: cite exact control/test IDs, version or retrieval date, and
  whether each item was assessed, partially assessed, not assessed, or not applicable.
- EEA EthTrust: claim conformance only when the engagement explicitly tested the
  applicable requirements and the report includes the necessary conformance evidence.
- CVSS: if used, publish the exact CVSS version, vector, score, and metric assumptions.
  Do not rename a custom likelihood-impact matrix as CVSS.
-->

### 6.4 Evidence Standard

A security finding is included only after independent internal validation and
human acceptance, and when the retained evidence states a specific affected
baseline, reachable mechanism, violated security property, evidence-supported
bounded consequence, relevant falsification result, and verification basis. The
verification method may vary by finding. The report does not infer stronger
deployment or state correspondence than the evidence supports.

### 6.5 Material Limitations and Open Assumptions

| ID | Limitation or Assumption | Affected Scope | Potential Effect on Conclusion | Status |
|---|---|---|---|---|
| {{LIM_01}} | {{LIMITATION_OR_OPEN_ASSUMPTION}} | {{SCOPE}} | {{EFFECT}} | {{OPEN_RESOLVED_OR_CLIENT_ACCEPTED_STILL_APPLICABLE}} |

A client-accepted limitation remains applicable and must remain visible in the
final conclusion unless later evidence resolves it.

### 6.6 Time-Bounded Nature of the Assessment

This assessment was time-bounded and was not an exhaustive proof of correctness.
Absence of a reported finding does not guarantee absence of defects. Security can
also change through later code changes, deployment configuration, governance,
privileged-key handling, integrations, market conditions, or chain behavior.

<!-- PAGE BREAK -->

## 7. Risk, Exposure, Evidence, and Status Taxonomy

### 7.1 Original Severity

Severity describes the technical consequence and exploitability of a finding in
the affected audited baseline. It is recorded independently from remediation.

| Severity | Definition |
|---|---|
| Critical | Feasible exploitation can cause catastrophic or systemic loss, irreversible protocol control compromise, insolvency, or equivalent failure with little practical containment. |
| High | Feasible exploitation can cause material asset loss, unauthorized privileged effects, prolonged loss of availability, or a major invariant violation. |
| Medium | Exploitation can cause a meaningful security or economic invariant violation, but impact or feasibility is constrained by significant conditions. |
| Low | Exploitation has limited direct impact, requires restrictive conditions, or materially weakens defense in depth without independently causing a major loss. |
| Informational | A human-accepted security-relevant correctness or defense-in-depth item without a demonstrated exploitable consequence. It sits outside the impact/exploitability matrix. Pure gas, style, and documentation notes belong in System Considerations. |

#### Engagement-Specific Severity Matrix

| Impact / Exploitability | Low | Medium | High |
|---|---|---|---|
| Low | Low | Low | Medium |
| Medium | Low | Medium | High |
| High | Medium | High | Critical |

<!--
If the engagement uses another taxonomy, replace this section consistently and
state how it differs. Do not call this matrix CVSS. If CVSS is additionally used,
include the score and vector in each finding and explain any supplemental Web3
impact judgment.
-->

### 7.2 Deployment Exposure

| Exposure | Meaning |
|---|---|
| Confirmed Exposed | The vulnerable condition was verified against the identified reviewed deployment and immutable observation-state anchor. |
| Conditionally Exposed | Deployment applicability was verified at an immutable observation-state anchor, and exposure follows when the stated role, liquidity, timing, market, integration, or other conditions hold. |
| Not Exposed in Reviewed Deployment | The code-level issue exists, but facts verified for the identified deployment at an immutable observation-state anchor prevent the stated exploit path. |
| Not Deployed | The affected baseline was not identified in the reviewed deployments. |
| Unknown / Not Assessed | Available evidence was insufficient to bind deployment identity and state or determine deployment applicability. The reason must be stated. |

Confirmed Exposed, Conditionally Exposed, and Not Exposed in Reviewed Deployment
all require the deployment identifier and an immutable state anchor such as an EVM
block number/hash, Solana slot and account/program-data identifiers, or Sui
checkpoint/object versions. Without that binding, use Unknown / Not Assessed.

### 7.3 Verification Basis

| Basis | Meaning |
|---|---|
| Deployed-State Evidence | Evidence was bound to an identified deployed target and stated observation state. |
| Audited-Build Evidence | Evidence was bound to the exact audited source/build baseline without claiming live-state correspondence. |
| Reconstruction Evidence | The relevant target behavior was reproduced in a controlled reconstruction whose differences are stated. |
| Source/Specification Evidence | The mechanism follows from the exact source or specification and explicit assumptions; deployment applicability is reported separately. |
| Other | A different sufficient and reproducible basis is described precisely in the finding. |

These categories describe correspondence, not a universal ranking of proof
techniques. Multiple bases may apply to one finding.

### 7.4 Remediation Status

| Status | Meaning | Treated as Resolved? |
|---|---|---|
| Open | No complete remediation was provided or the issue remains reproducible. | No |
| Fixed - Verified | The exact remediation baseline was reviewed with a functioning, target-faithful method that covers the original mechanism and preconditions, and positive evidence shows the mechanism is closed or the violated property now holds. | Yes |
| Partially Fixed | The change reduces risk but does not fully address the reported mechanism or impact. | No |
| Acknowledged | The client confirmed awareness without a complete verified remediation. | No |
| Risk Accepted | The client explicitly accepted the residual risk. | No |
| Not Yet Retested | A remediation was reported but was not reviewed on the exact supplied baseline. | No |

### 7.5 Severity and Status Integrity

- Preserve the original severity after remediation.
- Do not mark a finding Fixed - Verified from a patch description, issue comment,
  client statement, or unreviewed commit alone.
- A single failed reproduction is not fix verification. Rule out harness/tool
  failure, stale fixtures, target drift, and weakened preconditions; retain a
  positive control or other evidence that the verification method still works.
- Record risk acceptance as a client decision, not as technical resolution.
- State residual risk when a finding is only partially fixed or when the fix
  introduces new assumptions.

<!-- PAGE BREAK -->

## 8. Detailed Findings

<!--
Duplicate the complete finding block below for every accepted security finding.
Use stable public IDs such as F-01. Do not expose internal candidate or target IDs.
Order findings by original severity, then by ID. Preserve IDs across report versions.
-->

### {{F_01}}: {{FINDING_TITLE}}

| Field | Value |
|---|---|
| Original Severity | **{{CRITICAL_HIGH_MEDIUM_LOW_OR_INFORMATIONAL}}** |
| Current Status | **{{OPEN_FIXED_VERIFIED_PARTIALLY_FIXED_ACKNOWLEDGED_RISK_ACCEPTED_OR_NOT_YET_RETESTED}}** |
| Deployment Exposure | {{EXPOSURE_OR_UNKNOWN_NOT_ASSESSED_WITH_REASON}} |
| Deployment/State Anchor | {{DEPLOYMENT_ID_AND_IMMUTABLE_BLOCK_SLOT_CHECKPOINT_OBJECT_VERSION_OR_NOT_ASSESSED_WITH_REASON}} |
| Verification Basis | {{ONE_OR_MORE_BASES_FROM_SECTION_7_3}} |
| Affected Baseline | {{IMMUTABLE_SOURCE_BUILD_PACKAGE_PROGRAM_BYTECODE_OR_DEPLOYMENT_REVISION}} |
| Precise Locator | `{{SOURCE_LOCATOR_BYTECODE_OFFSET_INSTRUCTION_TRANSACTION_PROGRAM_PACKAGE_OBJECT_VERSION_OR_MODEL_OBLIGATION}}` |
| Reported | {{YYYY_MM_DD}} |
| Remediation Baseline | {{FULL_IMMUTABLE_REVISION_OR_DIGEST_OR_NOT_APPLICABLE_WITH_REASON}} |
| Retest Date | {{YYYY_MM_DD_OR_NOT_YET_RETESTED}} |
| Standards Mapping | {{EXACT_CONTROL_IDS_OR_NOT_APPLICABLE_WITH_REASON}} |

#### Summary

{{ONE_PARAGRAPH_STATEMENT_OF_THE_BROKEN_PROPERTY_ROOT_MECHANISM_AND_IMPACT}}

#### Affected Components

- `{{PATH_CONTRACT_MODULE_FUNCTION_OR_ADDRESS}}` - {{SECURITY_RELEVANT_ROLE}}

#### Threat Scenario and Preconditions

**Threat actor:** {{ACTOR_AND_REQUIRED_PRIVILEGES}}

**Preconditions:**

1. {{PRECONDITION}}
2. {{PRECONDITION}}

**Security property violated:** {{PRECISE_INVARIANT_OR_REQUIRED_POSTCONDITION}}

#### Technical Description

{{MINIMUM_SUFFICIENT_CAUSAL_EXPLANATION_OF_REACHABILITY_STATE_TRANSITION_AND_FAILURE}}

<!--
Use stable source links pinned to the audited commit. Include short code excerpts,
state diagrams, formulas, or traces only when they materially improve understanding.
For a public report, redact exploit-enabling details while embargoed or while a
live system remains vulnerable. Explain the redaction at a high level.
-->

#### Impact

{{WHO_OR_WHAT_IS_AFFECTED_DIRECT_AND_SECOND_ORDER_CONSEQUENCES_AND_PRACTICAL_BOUNDS}}

#### Exploitability and Severity Rationale

{{REQUIRED_ACCESS_CAPITAL_TIMING_ORDERING_MARKET_STATE_USER_ACTION_AND_WHY_THE_MATRIX_YIELDS_THIS_SEVERITY}}

#### Verification Basis

{{RECIPIENT_APPROPRIATE_DISCLOSURE_CONTROLLED_DESCRIPTION_OF_EVIDENCE_SUCCESS_CONDITION_RESULT_AND_TARGET_BINDING}}

<!--
Do not publish secrets, raw private artifacts, or an immediately weaponizable
exploit recipe. A confidential report may point to a separately controlled
reproduction package. State material reconstruction differences and failed or
unresolved checks when they affect confidence.
-->

#### Recommendation

{{DESIRED_SECURITY_PROPERTY_AND_ONE_OR_MORE_PRACTICAL_REMEDIATION_OPTIONS}}

Where relevant, also recommend a regression property or test that would prevent
the same failure class from reappearing.

#### Client Response

{{CLIENT_RESPONSE_OR_NOT_PROVIDED_AS_OF_YYYY_MM_DD}}

#### Remediation Verification

**Revision reviewed:** {{FULL_COMMIT_PACKAGE_DIGEST_OR_NOT_APPLICABLE_WITH_REASON}}

**Changes relevant to this finding:** {{CONCISE_CHANGE_SUMMARY}}

**Verification performed:** {{METHOD_SCOPE_AND_RESULT}}

**Residual risk:** {{NO_RESIDUAL_RISK_IDENTIFIED_WITHIN_RETEST_SCOPE_OR_PRECISE_REMAINING_RISK}}

<!--
If no fix was reviewed, replace this subsection with:
"No remediation baseline was reviewed for this finding as of {{YYYY_MM_DD}}."

If a fix was reviewed, state whether surrounding or unrelated changes were outside
the retest. Do not imply a full re-audit from a targeted fix review.
-->

#### Disclosure Note

{{PUBLICATION_REDACTION_EMBARGO_OR_NOT_APPLICABLE_WITH_REASON}}

<!-- Repeat finding block as needed. -->

<!-- PAGE BREAK -->

## 9. System Considerations

<!--
Optional. Use for non-finding design, operational, maintainability, observability,
or defense-in-depth considerations. Do not place a demonstrated security invariant
violation here to reduce its visibility. Do not include these items in finding
severity counts.
-->

### {{OBS_01}}: {{CONSIDERATION_TITLE}}

**Category:** {{DESIGN_OPERATIONS_MAINTAINABILITY_OBSERVABILITY_OR_DEFENSE_IN_DEPTH}}

**Affected component:** {{COMPONENT}}

**Observation:** {{FACTUAL_OBSERVATION}}

**Why it matters:** {{SECURITY_OR_OPERATIONAL_RELEVANCE_WITHOUT_OVERSTATING_RISK}}

**Suggested improvement:** {{PROPORTIONATE_ACTION}}

**Client response:** {{RESPONSE_OR_NOT_PROVIDED_AS_OF_YYYY_MM_DD}}

<!-- PAGE BREAK -->

## 10. Remediation Review

### 10.1 Review Scope

{{EXACT_FIX_BASELINES_FINDINGS_RETESTED_AND_WHETHER_THE_REVIEW_WAS_TARGETED_OR_COMPREHENSIVE}}

### 10.2 Remediation Baselines

| Delivery | Date | Full Revision/Digest | Findings Addressed | Build/Deployment Binding |
|---|---|---|---|---|
| {{DELIVERY_NAME}} | {{YYYY_MM_DD}} | `{{FULL_COMMIT_OR_DIGEST}}` | {{FINDING_IDS}} | {{RESULT_OR_NOT_ASSESSED_WITH_REASON}} |

### 10.3 Retest Results

| ID | Original Severity | Remediation Claim | Verification Performed | Current Status | Residual Risk |
|---|---|---|---|---|---|
| {{F_01}} | {{SEVERITY}} | {{CLIENT_CHANGE_SUMMARY}} | {{RETEST_SCOPE}} | {{STATUS}} | {{RESIDUAL_RISK}} |

### 10.4 Retest Boundary

Unless expressly stated otherwise, remediation review was limited to the listed
findings and revisions. It does not constitute a full review of unrelated changes
or a new assessment of the entire system.

<!-- PAGE BREAK -->

## 11. Residual Risk and Conclusion

### 11.1 Unresolved Findings

{{OPEN_PARTIAL_ACKNOWLEDGED_RISK_ACCEPTED_AND_NOT_YET_RETESTED_FINDINGS_OR_NONE}}

### 11.2 Accepted Risks

{{CLIENT_ACCEPTED_RISKS_OWNER_DATE_AND_RATIONALE_OR_NONE}}

### 11.3 Remaining Assumptions and Limitations

{{ASSUMPTIONS_AND_LIMITATIONS_THAT_A_READER_MUST_RETAIN_WHEN_USING_THE_CONCLUSION}}

### 11.4 Final Conclusion

{{FINAL_BOUNDED_CONCLUSION_TIED_TO_SCOPE_BASELINE_REMEDIATION_STATUS_AND_LIMITATIONS}}

<!--
The conclusion should answer:
- What exact baseline was assessed?
- What material findings remain unresolved?
- Which remediation baseline, if any, was verified?
- What deployment exposure was established?
- Which limitations could change the reader's decision?

Do not convert "no finding identified" into a guarantee of security.
-->

<!-- PAGE BREAK -->

## 12. Disclosure Timeline

| Date | Event |
|---|---|
| {{YYYY_MM_DD}} | Assessment commenced |
| {{YYYY_MM_DD}} | Initial findings delivered privately |
| {{YYYY_MM_DD}} | Remediation baseline received |
| {{YYYY_MM_DD}} | Remediation review completed |
| {{YYYY_MM_DD}} | Final report delivered |
| {{YYYY_MM_DD}} | Public disclosure approved or embargo lifted |

{{ADDITIONAL_COORDINATED_DISCLOSURE_CONTEXT_OR_NOT_APPLICABLE_WITH_REASON}}

<!-- PAGE BREAK -->

## Appendix A: Report Target Manifest

| ID | Component | Source/Address | Revision/Digest | Included | Notes |
|---|---|---|---|---|---|
| {{PUB_01}} | {{COMPONENT}} | {{PUBLIC_LINK_OR_ADDRESS}} | `{{FULL_COMMIT_OR_DIGEST}}` | {{YES_NO_PARTIAL}} | {{NOTES}} |

<!--
Use recipient-appropriate IDs. In a public report they must be public-safe. This
appendix should identify the reviewed target without revealing internal
filesystem paths or unauthorized private links.
-->

## Appendix B: Standards Coverage (Optional)

**Standard:** {{STANDARD_NAME_EXACT_VERSION_AND_URL}}<br>
**Assessment date/access date:** {{YYYY_MM_DD}}

| Control/Test ID | Description | Applicability | Assessment Status | Evidence Summary or Report Reference |
|---|---|---|---|---|
| {{CONTROL_ID}} | {{SHORT_DESCRIPTION}} | {{APPLICABLE_NOT_APPLICABLE}} | {{ASSESSED_PARTIAL_NOT_ASSESSED}} | {{DISCLOSURE_APPROPRIATE_REFERENCE}} |

This mapping communicates assessment coverage only. It is not a certification or
conformance claim unless this report explicitly defines the conformance criteria,
tests every applicable requirement, and states the resulting basis.

## Appendix C: Tooling and Environment

| Tool/Environment | Version or Revision | Purpose | Material Configuration |
|---|---|---|---|
| {{TOOL_OR_RUNTIME}} | {{EXACT_VERSION}} | {{PURPOSE}} | {{FLAGS_PROFILE_CHAIN_SNAPSHOT_OR_OTHER}} |

<!--
List only tools and settings material to reproducing or interpreting the reported
results. Do not disclose private infrastructure, tokens, keys, usernames, local
paths, or internal agent/runtime orchestration.
-->

## Appendix D: Definitions

| Term | Definition |
|---|---|
| Audited baseline | The exact source, build, package, program, bytecode, or deployment artifact identified as in scope. |
| Deployment exposure | The observed applicability of a finding to an identified deployment and state, separate from code-level severity. |
| Original severity | The technical risk assigned to a finding in the affected audited baseline before remediation status is considered. |
| Remediation baseline | The exact revision supplied for fix review. |
| Targeted fix review | Review limited to the stated finding and relevant changes; not necessarily a full re-audit. |

## Appendix E: References

1. {{PROJECT_DOCUMENTATION_PINNED_VERSION_OR_ACCESS_DATE_AND_URL}}
2. {{PROTOCOL_SPECIFICATION_PINNED_VERSION_OR_ACCESS_DATE_AND_URL}}
3. {{STANDARD_OR_EXTERNAL_REFERENCE_EXACT_VERSION_AND_URL}}

## Appendix F: Limitations and Reliance

This report reflects a professional, time-bounded security assessment of the
specified scope and baseline using the methods described above. It is not a
guarantee that the system is free from vulnerabilities, nor does it replace
continuous testing, monitoring, secure operations, incident response, governance
controls, or review of future changes.

Findings and conclusions may depend on information, code, deployment data, and
assumptions supplied by the client or observable during the assessment period.
Material inaccuracies or later changes may affect the conclusions. Third-party
systems are not assessed unless expressly included in scope.

{{ENGAGEMENT_SPECIFIC_RELIANCE_LANGUAGE_REVIEWED_BY_COUNSEL_OR_NOT_APPLICABLE_WITH_REASON}}

<!--
FINAL RELEASE CHECKLIST - DELETE BEFORE PUBLICATION

Content integrity
[ ] Internal audit closure completed and approved.
[ ] Every published finding exists in the accepted-finding register.
[ ] Finding counts reconcile across Executive Summary, Overview, and Details.
[ ] Original severity, exposure, and remediation status are separate and accurate.
[ ] Every Fixed - Verified finding names the exact reviewed remediation revision.
[ ] Every conclusion is bounded to the audited baseline, scope, and limitations.
[ ] Open assumptions and material coverage limitations are visible.

Target integrity
[ ] Full commit hashes, package/program digests, compiler settings, and addresses
    are exact and independently checked.
[ ] Source-to-deployment binding is stated accurately or marked not assessed.
[ ] Scope changes and remediation deliveries appear in the revision/timeline tables.

Public safety and confidentiality
[ ] Publication approval and coordinated-disclosure conditions are satisfied.
[ ] Exploit-enabling details are redacted where required, without concealing the
    existence, severity, status, or high-level impact of a disclosed finding.
[ ] No secrets, private links, client-confidential communications, raw exploit
    artifacts, usernames, or local filesystem paths remain.
[ ] No internal candidate IDs, target IDs, triage metrics, agent/runtime provenance,
    internal evidence paths, or rejected hypotheses remain.

Document quality
[ ] No {{PLACEHOLDERS}}, authoring comments, empty headings, "TBD", or unchecked
    checklist items remain in the released artifact.
[ ] Dates use YYYY-MM-DD; addresses and hashes use the agreed canonical format.
[ ] Links and pinned source references resolve.
[ ] Tables, diagrams, code excerpts, headers, footers, and page breaks render cleanly.
[ ] Technical reviewer, report editor, client owner, and disclosure owner approvals
    are recorded where required.
[ ] The released file's digest and canonical publication URL are recorded.
-->
