# KURI Smart Contracts

## What is KURI?

KURI is a digital version of a traditional community savings group, also known as a Rotating Savings and Credit Association (ROSCA). In this system, members contribute money regularly, and one member receives the entire pool on a rotating basis.

## How Does It Work?

1. **Joining**: Members join during a launch period.
2. **Regular Payments**: Each member makes regular payments (weekly, monthly, etc.).
3. **Winner Selection**: At the end of each payment period, one member is randomly selected to receive the entire pool.
4. **Fair Distribution**: Each member can only win once until everyone has had a turn.

## The KuriCore Contract

The main contract, `KuriCore.sol`, handles all the important functions:

### Key Features

- **Member Management**: Tracks who has joined and their payment status.
- **Payment Handling**: Records when members make their payments.
- **Random Selection**: Uses Chainlink VRF (a secure random number generator) to fairly select winners.
- **Winner Tracking**: Ensures each member can only win once per cycle.
- **Admin Controls**: Allows administrators to manage the group and handle special cases.

### Main Functions

- **Request Membership**: Join the KURI group during the launch period.
- **Make Payments**: Contribute your share for each period.
- **Claim Winnings**: Receive your funds when you're selected as a winner.
- **Flag Non-Paying Members**: Administrators can mark members who don't pay.
- **Withdraw Funds**: Administrators can withdraw remaining funds after the cycle is complete.

### Security Features

- **Role-Based Access**: Different functions are limited to specific roles (admin, initializer, etc.).
- **Payment Verification**: The system checks that members have paid before they can win.
- **Bitmap Storage**: Uses an efficient storage method to save on transaction costs.
- **No Duplicate Winners**: The selection system ensures each member wins exactly once.

## Technical Implementation

The contract uses several advanced techniques to ensure fairness and efficiency:

- **Bitmap Storage**: Efficiently tracks payments and claims using binary operations.
- **Random Selection Without Replacement**: Ensures each member is selected exactly once.
- **State Management**: Tracks the current state of the KURI (launch, active, completed).
- **Time-Based Controls**: Uses timestamps to manage intervals and payment periods.

## Getting Started

To interact with the KURI contract:

1. Connect your wallet to the application.
2. Request membership during the launch period.
3. Make your payments when they're due.
4. Wait for your turn to receive the pool.
5. Claim your winnings when selected.

## Testing

The contract includes comprehensive tests to ensure everything works correctly. These tests check all aspects of the system, including:

- Membership requests
- Payment processing
- Random selection
- Winner verification
- Admin functions
