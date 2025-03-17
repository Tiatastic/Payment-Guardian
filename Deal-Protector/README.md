# Service Agreement Smart Contract

This smart contract enables secure service agreements between clients and service providers on the Stacks blockchain, with built-in milestone tracking, dispute resolution, and escrow functionality.

## Overview

The Service Agreement Smart Contract provides a decentralized platform for establishing and managing service-based agreements with the following features:

- **Milestone-based payment structure**: Break down projects into 5 verifiable milestones
- **Escrow mechanism**: Client funds are securely held until services are delivered
- **Dispute resolution**: Built-in arbitration process for resolving conflicts
- **Transparent tracking**: Monitor agreement status and milestone completion

## Contract Status Lifecycle

An agreement moves through the following statuses:

1. **Pending Funding** (0): Agreement created but awaiting client funding
2. **In Progress** (1): Agreement funded and work has begun
3. **Completed** (2): All milestones completed and ready for payment
4. **Cancelled** (3): Agreement terminated before completion
5. **Disputed** (4): Agreement under dispute resolution

## How It Works

### For Clients

1. **Create an Agreement**
   ```clarity
   (establish-service-agreement agreement-id provider-address total-value agreement-duration milestone-list)
   ```
   - `agreement-id`: Unique identifier for the agreement
   - `provider-address`: Principal address of the service provider
   - `total-value`: Total payment amount in microSTX
   - `agreement-duration`: Duration in blocks
   - `milestone-list`: List of 5 milestones with titles and fees

2. **Fund the Agreement**
   ```clarity
   (fund-agreement agreement-id deposit-amount)
   ```
   Deposit funds into escrow for the agreement. Multiple deposits can be made until the total value is reached.

3. **Release Payment**
   ```clarity
   (release-payment agreement-id)
   ```
   Release funds to the provider once all milestones are completed.

4. **File a Dispute**
   ```clarity
   (file-dispute agreement-id dispute-description)
   ```
   If issues arise, file a detailed dispute for arbitration.

5. **Cancel Agreement**
   ```clarity
   (cancel-agreement agreement-id)
   ```
   Can only be done during the "Pending Funding" stage.

### For Service Providers

1. **Complete Milestones**
   ```clarity
   (complete-milestone agreement-id milestone-index)
   ```
   Mark each milestone as complete to track progress.

2. **File a Dispute**
   ```clarity
   (file-dispute agreement-id dispute-description)
   ```
   Providers can also file disputes if needed.

### For Contract Owner (Arbitrator)

1. **Resolve Disputes**
   ```clarity
   (arbitrate-dispute agreement-id resolution-text client-refund-rate)
   ```
   - `resolution-text`: Explanation of the arbitration decision
   - `client-refund-rate`: Percentage (0-100) of funds to be returned to client

## Read-Only Functions

- `(get-agreement-info agreement-id)`: Get full agreement details
- `(get-secured-payment agreement-id)`: Check amount in escrow
- `(get-dispute-info agreement-id)`: Get dispute details if any

## Error Codes

- `100`: Permission denied
- `101`: Invalid status for the requested operation
- `102`: Payment too low
- `103`: Duplicate agreement ID
- `104`: Agreement not found
- `105`: Milestone index out of bounds
- `106`: Invalid parameters
- `107`: Invalid provider address
- `108`: Milestone validation failed

## Security Features

- Milestone fees must sum to the total contract value
- Milestone titles must be properly defined
- Dispute filing is time-limited (deadline = completion_block + 144 blocks)
- Proper authorization checks for all operations
- Funds are secured in the contract until explicitly released

## Usage Example

```clarity
;; Client creates an agreement
(establish-service-agreement 
  u1 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 
  u1000000 
  u1000 
  (list 
    {milestone-title: "Requirement Gathering", milestone-fee: u200000, milestone-status: false}
    {milestone-title: "Design Phase", milestone-fee: u200000, milestone-status: false}
    {milestone-title: "Development", milestone-fee: u300000, milestone-status: false}
    {milestone-title: "Testing", milestone-fee: u200000, milestone-status: false}
    {milestone-title: "Deployment", milestone-fee: u100000, milestone-status: false}
  )
)

;; Client funds the agreement
(fund-agreement u1 u1000000)

;; Provider completes milestones
(complete-milestone u1 u0)
(complete-milestone u1 u1)
(complete-milestone u1 u2)
(complete-milestone u1 u3)
(complete-milestone u1 u4)

;; Client releases payment
(release-payment u1)
```

## Important Notes

- All milestone fees must add up to the total agreement value
- Agreement duration is measured in blocks, not time
- Dispute deadline is set to approximately 1 day after the completion block (144 blocks)
- Funds are held in the contract until explicitly released or redistributed through arbitration