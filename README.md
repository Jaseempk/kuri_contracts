# Kuri System

## Overview

The Kuri System is a modern implementation of a Rotating Savings and Credit Association (ROSCA) on the blockchain. This system allows community members to form savings groups where everyone contributes funds regularly, and members take turns receiving the entire pool of contributions.

## What is a ROSCA?

A Rotating Savings and Credit Association (ROSCA) is a traditional group-based financial arrangement common in many communities worldwide. In a ROSCA:

1. A group of people agree to contribute a fixed amount of money regularly (weekly, monthly, etc.)
2. At each contribution interval, the total pool is given to one member
3. The process continues until every member has received the pool once
4. This creates a combination of savings discipline and access to larger sums of money

## How Kuri Works

The Kuri system implements this concept on the blockchain with several key improvements:

- **Transparent Process**: All transactions and winner selections are fully transparent and verifiable
- **Fair Selection**: Winners are selected using Chainlink's verifiable random function (VRF)
- **Defaulter Protection**: System can identify and flag members who don't make their payments
- **Smart Contract Security**: Rules enforced through code rather than social pressure

## User Roles

### 1. Creator

- Deploys a new Kuri instance
- Has admin privileges
- Can flag defaulters and perform administrative functions

### 2. Initializer

- Responsible for finalizing the Kuri setup after members join
- Can be the same as the Creator or a different address

### 3. Members

- Join the Kuri by requesting membership
- Make regular contributions
- Have a chance to win the pool in each cycle

## User Flows

### Creating a New Kuri

1. A creator uses the KuriCoreFactory to deploy a new Kuri instance by calling:

   ```solidity
   initialiseKuriMarket(
       uint64 kuriAmount,           // Total amount to be collected
       uint16 kuriParticipantCount, // Number of participants required
       uint8 intervalType           // 0 for weekly, 1 for monthly
   )
   ```

2. This deploys a new KuriCore contract with initial parameters including:
   - The total amount to be collected (kuriAmount)
   - Required number of participants (kuriParticipantCount)
   - Payment interval type (weekly or monthly)
   - The creator's address becomes the admin
   - The caller becomes the initializer

### Joining a Kuri

1. Users can join during the launch period (3 days after creation) by calling:

   ```solidity
   requestMembership()
   ```

2. Once approved, they become active members with a unique index
3. Membership requests are only accepted until the maximum participant count is reached

### Initializing the Kuri

1. After the launch period (3 days), the initializer calls:

   ```solidity
   initialiseKuri()
   ```

2. The system checks if enough members have joined:
   - If not enough members joined, the Kuri enters a "LAUNCHFAILED" state
   - If enough members joined, the Kuri becomes "ACTIVE" and sets up all timing parameters

### Making Contributions

1. When an interval begins, members must make their payment by calling:

   ```solidity
   userInstallmentDeposit()
   ```

2. The system automatically:
   - Checks that the user is an accepted member
   - Verifies the deposit interval has been reached
   - Ensures the user hasn't already paid for this interval
   - Transfers the required amount from the user to the contract

### Selecting a Winner

1. After the deposit period plus a 3-day delay, the admin can trigger the winner selection:

   ```solidity
   kuriNarukk()
   ```

2. This initiates a request to Chainlink VRF for a secure random number
3. When the random number is received, the contract automatically:
   - Selects a winner from the active participants who have paid for the current interval
   - Updates the winner's status
   - Prepares for the next interval

### Claiming Winnings

1. After being selected as a winner, a user can claim their winnings:

   ```solidity
   claimKuriAmount(uint16 intervalIndex)
   ```

2. The contract verifies:
   - The user has won a slot but hasn't already claimed
   - The interval index is valid
   - The user has made all required payments
3. Once verified, the full amount is transferred to the winner

### Handling Defaulters

1. If a member fails to make their contribution, the admin can flag them:

   ```solidity
   flagUser(address user, uint16 intervalIndex)
   ```

2. This:
   - Marks the user as flagged
   - Removes them from active participants
   - Prevents them from participating in future selections

### Completing the Cycle

1. After all intervals have completed, the Kuri enters the "COMPLETED" state
2. The admin can withdraw any remaining funds:
   ```solidity
   withdraw()
   ```

## Technical Details

### Key Constants

- **WEEKLY_INTERVAL**: 7 days
- **MONTHLY_INTERVAL**: 30 days
- **LAUNCH_PERIOD_DURATION**: 3 days
- **RAFFLE_DELAY_DURATION**: 3 days (time after deposit deadline before winner selection)

### States

1. **KuriState**:

   - INLAUNCH: Initial state during member recruitment
   - LAUNCHFAILED: State when not enough members joined during launch
   - ACTIVE: Normal operating state after successful initialization
   - COMPLETED: Final state after all cycles are complete

2. **UserState**:
   - NONE: Default state
   - ACCEPTED: User is an active member of the Kuri
   - REJECTED: User has been rejected from the Kuri
   - FLAGGED: User has been flagged as a defaulter

### Payment Tracking

The system uses bitmap storage for gas-efficient payment tracking:

- Each bit in the bitmap represents a user's payment status
- This approach reduces gas costs for operations that check or update user status

### Randomness

Winner selection uses Chainlink VRF (Verifiable Random Function) to ensure:

- Transparent and provably fair selection process
- No possibility of manipulation by administrators or participants
- Secure, decentralized source of randomness

## Security Considerations

1. **Payment Token**:

   - The system uses a fixed token address (USDC)
   - Users must approve the contract to spend their tokens before making deposits

2. **Access Control**:

   - Uses OpenZeppelin's AccessControl for role-based permissions
   - DEFAULT_ADMIN_ROLE: Has full administrative control
   - INITIALISOR_ROLE: Can initialize the Kuri after launch period

3. **Timing Protection**:
   - Enforces waiting periods between key actions
   - Prevents early withdrawals or premature winner selection

## Getting Started

### Prerequisites

- An Ethereum wallet (MetaMask, etc.)
- USDC tokens for contributions
- Basic understanding of blockchain transactions

### Participating in a Kuri

1. **Find a Kuri**: Find the address of a recently deployed Kuri that's still in the launch period
2. **Request Membership**: Call `requestMembership()` to join
3. **Make Deposits**: Once the Kuri is active, make regular contributions when intervals begin
4. **Monitor Events**: Keep track of winner announcements through contract events
5. **Claim Winnings**: If selected, claim your winnings by providing the interval index

### Creating Your Own Kuri

1. **Deploy**: Use the KuriCoreFactory to create a new Kuri
2. **Recruit**: Share your Kuri address with potential members
3. **Initialize**: After the launch period, call `initialiseKuri()` to start the cycles
4. **Administer**: Monitor participation and flag defaulters as needed

## Events

The system emits several events to track important activities:

- **KuriMarketDeployed**: When a new Kuri is created
- **KuriInitialised**: When a Kuri is successfully initialized
- **KuriInitFailed**: When a Kuri fails to initialize due to insufficient participation
- **MembershipRequested**: When a user requests to join a Kuri
- **UserDeposited**: When a user makes a contribution
- **RaffleWinnerSelected**: When a winner is selected for an interval
- **KuriSlotClaimed**: When a winner claims their funds
- **UserFlagged**: When a user is flagged as a defaulter

## Glossary

- **ROSCA**: Rotating Savings and Credit Association
- **Kuri**: A specific implementation of a ROSCA on the blockchain
- **Interval**: The time period between contribution cycles (weekly or monthly)
- **Slot**: A position in the rotation where a member receives the pool

## Troubleshooting

### Common Issues

1. **Can't Join a Kuri**

   - Check if the Kuri is still in the launch period
   - Verify if the Kuri has already reached maximum participants

2. **Can't Make a Deposit**

   - Ensure the deposit interval has been reached
   - Check if you've already made a deposit for this interval
   - Confirm you have sufficient USDC balance and have approved the contract

3. **Can't Claim Winnings**
   - Verify you've been selected as a winner
   - Ensure you've made all required payments
   - Check that you haven't already claimed for this interval

---

This project implements a blockchain-based ROSCA system that provides transparency, security, and fairness to a traditional community savings method. By leveraging smart contracts and decentralized randomness, it creates a trust-minimized platform for collaborative saving and credit rotation.
