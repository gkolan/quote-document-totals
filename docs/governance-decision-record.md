# License and support decision record

This record gives the repository owner concrete choices required before the first supported release. It does not select a license, promise support, or replace legal review.

GitHub explains that public source without a license remains under default copyright and cannot be treated as open source. The owner should confirm authorship and third-party obligations before adding a license. Use the exact approved text from an authoritative source such as the [SPDX License List](https://spdx.org/licenses/) rather than rewriting legal terms.

## Decision 1: distribution license

| Option                            | Practical effect to review                                                                          | Repository changes after approval                                                                                                                                     |
| --------------------------------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apache License 2.0 (`Apache-2.0`) | Permissive reuse with an express patent-license framework and notice conditions                     | Add the official `LICENSE`, add `NOTICE` if required by the reviewed attribution inventory, set `package.json.license`, and update README status                      |
| MIT License (`MIT`)               | Short permissive grant requiring preservation of its copyright and permission notice                | Add the official `LICENSE` with approved copyright holder/year, set `package.json.license`, and update README status                                                  |
| No public license                 | Default copyright remains; external reproduction, distribution, and derivative work are not granted | Keep the release builder blocked, state that no installable public release is offered, and define a separate written commercial agreement if distribution is intended |

Authoritative references: [GitHub licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository), [SPDX MIT text](https://spdx.org/licenses/MIT.html), and [SPDX Apache-2.0 text](https://spdx.org/licenses/Apache-2.0.html).

Before deciding, the owner records:

- legal owner and approved copyright notice;
- whether every contributor had authority to contribute under the selected terms;
- third-party code, examples, images, generated material, and dependencies with their licenses;
- patent-policy requirements;
- whether trademark rights or Salesforce marks need separate wording; and
- reviewer name, decision date, and first version covered.

**Owner decision:** Pending
**Approved identifier and exact source:** Pending
**Copyright holder/year:** Pending
**Legal review or documented waiver:** Pending
**Effective release:** Pending

## Decision 2: support model

Select one operating model and publish its actual contact routes. Do not list a response target that the maintainer cannot measure and staff.

| Option                     | Public expectation                                                                                 | Required implementation                                                                                                                                                 |
| -------------------------- | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Community, best effort     | Public issues are triaged without a response-time commitment; security reports use a private route | Publish `SUPPORT.md`, enable the chosen issue forms, configure the private security contact, state the supported-version window, and label unsupported org combinations |
| Maintainer service targets | Public and private requests have measured acknowledgement targets but no contractual SLA           | Name the on-call owner, business hours/time zone, severity definitions, response targets, holiday coverage, escalation path, and monthly reporting                      |
| Contracted support         | Entitled organizations receive contractual service levels through a named support system           | Publish the boundary between public community help and contracted support; have counsel review service terms, privacy handling, subcontractors, and liability           |
| No support offering        | The source is provided without an operational support channel                                      | State this prominently and avoid “supported release” language; keep the security reporting route required by `SECURITY.md` clear                                        |

The selected policy must answer:

1. Which release lines receive defect and security fixes, and for how long?
2. Which Salesforce API, CPQ versions, currencies, locales, browsers, and document integrations are in scope?
3. Where do installation questions, defects, feature requests, and confidential vulnerabilities go?
4. What data may a reporter attach, and how are accidental customer or Quote data handled and deleted?
5. What severity definitions, response targets, maintenance windows, and escalation paths apply?
6. Who owns release decisions, incident communication, and end-of-support notices?

**Owner decision:** Pending
**Public intake route:** Pending
**Private security route:** Pending
**Supported-version window:** Pending
**Response commitment:** Pending
**Effective release:** Pending

## Release gate

The source-release builder requires a root `LICENSE`. After the owner completes both decisions:

1. add the approved license and support files;
2. update package metadata and public status claims;
3. run documentation, dependency, and release-builder tests;
4. obtain the protected Salesforce validation evidence;
5. create the reviewed version tag; and
6. build and attach the checksum manifest from that immutable tag.

The release reviewer must reject a mismatch among the approved decision, root files, package metadata, README, security policy, hosted release notes, and source archive.
