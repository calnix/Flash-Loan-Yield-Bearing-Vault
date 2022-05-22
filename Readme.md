# Objective
Refactor the Fractional Wrapper from assignment #4 into a Proportional Ownership Flash Loan Server, conforming to specifications ERC3156 and ERC4626.

1) Refactor the Fractional Wrapper into an ERC3156 Flash Loan Server: https://eips.ethereum.org/EIPS/eip-3156
2) The underlying is the token available for flash lending -> e.g. underlying = DAI  | wrapper token = yvDAI
3) Fee is a constant 0.1%
4) Make the contract a proportional ownership contract: When users deposit underlying, they get a proportion of wrapper tokens, based on the following:
> wrapperMinted / wrapperSupply == underlyingDeposited / underlyingInWrapper

## What does this mean?
Essentially, the Fractional wrapper operates as per usual; accepting deposits, withdrawals and so forth as specified in ERC4626.
Additionally, now it can offer flashloans, conforming to ERC3156. 
The flashlending token will be of the same underlying that the FractionWrapper operates upon.

### For example: 
Users can deposit DAI, which is the underlying, for which they will receive yvDAI (wrapped tokens) as per:
> wrapperMinted = (underlyingDeposited * wrapperSupply) / underlyingInWrapper 

Other users can flash borrow DAI that has been deposited, for whatever purpose they have in mind.
They will be charged a fee of 0.1% for this service. Vault accumulates fees, which can then be partially passed on to depositors as yield, while the rest is retained as revenue.
Additionally, throught the accumulation of this fee, the underlying deposits of the vault will increase, thereby altering the exchange rate eqn.

> wrapperMinted = underlyingDeposited / underlyingInWrapper * wrapperSupply

> wrapperMinted = (underlyingDeposited * wrapperSupply) / underlyingInWrapper 

# Contracts

## FlashLoanVault.sol
Flash loan lender must implement IERC3156FlashLender -> lender interface must be implemented by services wanting to provide a flash loan. 

### flashLoan()
flashLoan() function executes the flash loan. [A borrower would call on this function to execute a flash loan (via flashBorrow)]
1. The receiver address must be a contract implementing the borrower interface. Any arbitrary data may be passed in addition to the call.
2. The only requirement for the implementation details of the function are that you have to call the onFlashLoan callback from the receiver:
`require(receiver.onFlashLoan(msg.sender, token, amount, fee, data) == keccak256("ERC3156FlashBorrower.onFlashLoan"), "IERC3156: Callback failed");`
After the callback, the flashLoan function must take the amount + fee token from the receiver, or revert if this is not successful.

#### What happens when flashLoan() is called?
1. mint the requested amount to the borrower
2. execute the onFlashLoan callback and verify its return value
3. check if the repayment is approved
4. reduce the allowance by the repayment amount and burn it

### flashfee & _flashfee()
These two functions are used to set the fee for each token the lender is willing to lend out. In our implementation we will only be lending a single token, DAI, hence the fee calculation is static, reflecting 0.1%.

### maxFlashLoan()
Returns the maximum amount of a token the lender is able to offer in a flash loan - dependent on the lender's holdings.
Also, it is used to tell when a token is not support (or does not have liquidity) by returning a zero.

## FlashLoanBorrower.sol
Must implement borrower interface: IERC3156FlashBorrower.sol. 
The borrower interface consists of only of 1 callback function: onFlashLoan(). We will overwrite this in our implementation.

### onFlashLoan()
This does three things:
1. verify the sender is actually the lender
2. verify the initiator for the flash loan was actually our contract
3. return the pre-defined hash to verify a successful flash loan

We could further implement additional logic here based on the passed data field if required. Essentially, what do we do with the flash loan once we have received it.

### flashBorrow()
For the borrower to initate the flash loan, we will use flashBorrow().
This function calculates the fee to be paid in advance for the loan, and approves the amount+fee as an allowance of the lender.
For the transaction to not revert, inside the onFlashLoan the contract must approve amount + fee of the token to be taken by msg.sender(lender).

## Flow
1. Borrower contract executes flashBorrow():
    - total repayment amount (fee + amount) is calculated and approved as allowance for lender to claw back via transferFrom()
    - lender.flashloan() is called, initiating the flashloan service on the lender contract.
2. flashLoan() checks the following:
    - Tokens that was being requested for flash loan are supported & calculates fee to be charged
    - Transfers the loan amount to the receiver (via .transfer)
    - Call back to receiver: calls receiver.onFlashLoan() which does the following:
        - verifying the sender is the correct lender
        - verifying the initiator for the flash loan was actually the receiver contract 
        - returns keccak256("ERC3156FlashBorrower.onFlashLoan")
    - Finally, amount+fee is transferred from the receiver to the lender (via .transferFrom)
    - returns true on success.




