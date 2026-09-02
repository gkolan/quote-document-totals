# Security

## Report a security concern

Do not open a public GitHub issue for a possible security problem.

Use GitHub's private security reporting feature if it is enabled for this repository. If it is not enabled, contact the repository owner privately through their GitHub profile and ask for a secure reporting method. Do not include credentials, access tokens, customer data, or full Salesforce record exports in the first message.

Include:

- A short description of the concern.
- The affected Salesforce item or file.
- Steps that show the problem using test data.
- The possible effect on Salesforce access, Quote data, generated documents, or customer information.
- A safe way to contact you.

## Keep Salesforce information private

- Never commit `.env` files, authentication files, access tokens, private keys, org exports, or debug logs containing record data.
- Use made-up accounts, products, Quotes, and Quote Lines in examples.
- Remove org URLs, user names, record IDs, and customer information from screenshots and test results.
- Test permission-set and sharing changes with a non-administrator user before production deployment.

Security fixes should be tested in a Salesforce CPQ sandbox or test org before production deployment.
