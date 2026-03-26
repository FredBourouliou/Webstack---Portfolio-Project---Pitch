# Problem Statement

## The Freelancer Invoicing Problem

France has over **2 million auto-entrepreneurs** (micro-entrepreneurs). They all share the same pain points:

### 1. Invoicing is tedious

Most freelancers use Word/Excel templates or overpriced SaaS tools costing €10-30/month. Creating a legally compliant French invoice requires specific mandatory fields (SIRET, TVA mention, payment terms), and getting them wrong can result in fines.

### 2. URSSAF calculations are confusing

Social contribution rates vary by activity type:

| Activity | URSSAF Rate |
|----------|-------------|
| Services (BNC) | 22.0% |
| Commercial (BIC vente) | 12.3% |
| Commercial (BIC services) | 21.2% |
| Liberal professions (CIPAV) | 21.1% |

Most freelancers calculate this manually or wait for the quarterly URSSAF bill to find out what they owe.

### 3. VAT threshold tracking is error-prone

French auto-entrepreneurs are VAT-exempt below certain thresholds:

| Activity | Standard Threshold | Increased Threshold |
|----------|-------------------|---------------------|
| Services | €36,800 | €39,100 |
| Commerce | €91,900 | €101,000 |

Cross the threshold mid-year and you must start charging VAT immediately. Miss it and you face penalties, back-payments, and administrative headaches. Most freelancers track this in spreadsheets — or don't track it at all.

### 4. Existing tools are bloated

The average invoicing SaaS:
- Ships **200+ KB of JavaScript** to the browser
- Requires **500+ npm packages** to build
- Needs a **database server**, a **cache layer**, and a **queue system**
- Costs **€10-30/month** for basic features

All of this for what is fundamentally an **arithmetic problem**: multiply quantities by rates, apply a tax percentage, sum the results.

### The Core Issue

**Financial calculations demand precision.** Yet most web applications use IEEE 754 floating-point arithmetic, which produces silent rounding errors:

```
// JavaScript
0.1 + 0.2 = 0.30000000000000004
1.1 * 1.1 = 1.2100000000000002
```

For a single invoice, the error is negligible. Across thousands of invoices, it accumulates. Banks solved this problem in 1959 with COBOL's fixed-point decimal arithmetic. Most modern web frameworks still haven't.
