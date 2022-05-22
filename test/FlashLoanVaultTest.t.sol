// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console2.sol";

import "src/FlashBorrower.sol";
import "src/FlashLoanVault.sol";

import "src/IERC3156FlashBorrower.sol";
import "src/DAIToken.sol";

import "test/USDC.sol";
import "test/FailedFlashBorrower.sol";

using stdStorage for StdStorage;


abstract contract StateZero is Test, FlashLoanVault {
        
    DAIToken public dai;
    USDC public usdc;

    FlashLoanVault public vault;
    FlashBorrower public borrower;
    FailedFlashBorrower public failedBorrower;

    address user;
    address deployer;
    uint userTokens;
    uint vaultTokens;

    constructor() FlashLoanVault(IERC20(dai),"yvDAI", "yvDAI") {}

    function setUp() public virtual {
        dai = new DAIToken();
        vm.label(address(dai), "Dai contract");

        vault = new FlashLoanVault(IERC20(dai), "yvDAI", "yvDAI");
        vm.label(address(vault), "FlashLoanVault contract");

        borrower = new FlashBorrower(IERC3156FlashLender(address(vault)));
        vm.label(address(borrower), "FlashBorrower contract");

        user = address(1);
        vm.label(user, "user");
        
        deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
        vm.label(deployer, "deployer");

        // user: mint and approve
        userTokens = 100 * 1e18;
        dai.mint(user, userTokens);
        vm.prank(user);
        dai.approve(address(vault), type(uint).max);

        // vault: mint starting capital of underlying asset
        vaultTokens = 1000 * 1e18;
        //dai.mint(address(vault), vaultTokens);
        dai.mint(deployer, vaultTokens);
        vm.prank(deployer);
        dai.approve(address(vault), type(uint).max);
        vault.deposit(vaultTokens, deployer);
        
    }
}


contract StateZeroTest is StateZero {   
    // Note: User interacts directly with vault in this scenario; no intermediary parties.
    // deploy: user is both caller and receiver
    // withdraw: user is both the owner and receiver

    function testCannotWithdraw(uint amount) public {
        console2.log("User should be unable to withdraw without any deposits made");
        amount = bound(amount, 1, dai.balanceOf(user));

        vm.expectRevert("ERC20: Insufficient balance");
        vm.prank(user);
        vault.withdraw(amount, user, user);
    }

    function testCannotRedeem(uint amount) public {
        console2.log("User should be unable to redeem without any deposits made");
        amount = bound(amount, 1, dai.balanceOf(user));

        vm.expectRevert("ERC20: Insufficient balance");
        vm.prank(user);
        vault.redeem(amount, user, user);
    }
  
    function testDeposit() public {
        console2.log("User deposits DAI into Vault");       
        uint shares = convertToShares(userTokens/2);
        
        vm.expectEmit(true, true, false, true);
        emit Deposit(user, user, userTokens/2, shares);
        
        vm.prank(user);
        vault.deposit(userTokens/2, user);
        assertTrue(vault.balanceOf(user) == dai.balanceOf(user));
    }

    function testMint() public {
        console2.log("Test minting of shares to user");
        uint shares = convertToShares(userTokens/2);

        vm.expectEmit(true, true, false, true);
        emit Deposit(user, user, userTokens/2, shares);
        
        vm.prank(user);
        vault.mint(userTokens/2, user);
        assertTrue(vault.balanceOf(user) == dai.balanceOf(user));
    }

    function testAsset() public {
        assertTrue(vault.asset() == address(dai));
    }

    function testTotalAssets() public {
        assertTrue(vault.totalAssets() == vaultTokens);
    }
}


abstract contract StateDeposited is StateZero {
    
    function setUp() public override virtual {
        super.setUp();

        //user deposits into vault
        vm.prank(user);
        vault.deposit(userTokens/2, user);
    }
}


contract StateDepositedTest is StateDeposited {

    function testCannotWithdrawInExcess() public {
        console2.log("User cannot withdraw in excess of what was deposited - burn() will revert");
        vm.prank(user);
        vm.expectRevert("ERC20: Insufficient balance");
        vault.withdraw(userTokens, user, user);
    }

    function testCannotRedeemInExcess() public {
        console2.log("User cannot redeem in excess of what was deposited - burn() will revert");
        vm.prank(user);
        vm.expectRevert("ERC20: Insufficient balance");
        // since ex_rate = 1 -> qty of userTokens as shares = qty of userTokens | trivial conversion
        vault.redeem(userTokens, user, user);
    }

    function testWithdraw() public {
        console2.log("User withdraws his deposit");
        uint shares = convertToShares(userTokens/2);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, userTokens/2, shares);
        
        vm.prank(user);
        vault.withdraw(userTokens/2, user, user);

        assertTrue(vault.balanceOf(user) == 0);
        assertTrue(dai.balanceOf(user) == userTokens);
    }

    function testRedeem() public {
        console2.log("User redeems his shares, for his deposit");
        // since ex_rate = 1 -> qty of userTokens as shares = qty of userTokens | trivial conversion
        // meaning: assets == userTokens/2 == shares
        uint assets = convertToAssets(userTokens/2);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, assets, userTokens/2);
        
        vm.prank(user);
        vault.redeem(assets, user, user);

        assertTrue(vault.balanceOf(user) == 0);
        assertTrue(dai.balanceOf(user) == userTokens);
    }

    function testTotalAssets() public {
        assertTrue(vault.totalAssets() == vaultTokens + userTokens/2);
    }

    function testMaxWithdraw() public {
        assertTrue(vault.maxWithdraw(user) == convertToAssets(userTokens/2));
    }

    function testMaxRedeem() public {
        assertTrue(vault.maxRedeem(user) == userTokens/2);
    }

    function testCannotFlashLoan() public {
        console2.log("Borrower initiates flashloan - fails due to having 0 DAI");

        vm.expectRevert("ERC20: Insufficient balance");
        borrower.flashBorrow(address(dai), 100 * 1e18);
    }
}



abstract contract StateFlashLoan is StateDeposited {
    function setUp() public override virtual {
        super.setUp();

        // borrower needs to repay loan + fee: 
        // initialize with some DAI for fee repayment
        dai.mint(address(borrower), 100 * 1e18);

        usdc = new USDC();
        vm.label(address(usdc), "USDC contract");
        
        failedBorrower = new FailedFlashBorrower(IERC3156FlashLender(address(vault)));
        vm.label(address(failedBorrower), "Failed FlashBorrower contract");
    }
}

contract StateFlashLoanTest is StateFlashLoan {
    
    function testCannotBorrowUnsupportedToken() public {
        console2.log("Borrower initiates flashloan with USDC token");

        vm.expectRevert("FlashLender: Unsupported currency");
        borrower.flashBorrow(address(usdc), 100 * 1e18);
    }

    function testCannotCalculateFeeUnsupportedToken() public {
        console2.log("flashfee() reverts when used with USDC token");

        vm.expectRevert("FlashLender: Unsupported currency");
        vault.flashFee(address(usdc), 100 * 1e18);
    }

    function testRevertOnFailedTransfer() public {
        console2.log("Flashloan reverts on failed transfer of loan to receiver");

        dai.setFailTransfers(true);
        vm.expectRevert("FlashLender: Transfer failed");
        borrower.flashBorrow(address(dai), 100 * 1e18);
    }

    function testLenderIsNotCaller() public {
        console2.log("onFlashLoan() reverts since msg.sender is not registered lender");

        vm.expectRevert("FlashBorrower: Untrusted lender");
        vm.prank(user);
        borrower.onFlashLoan(address(borrower), address(dai), 1000, 1, bytes("test"));
    }

    function testInitiatorIsNotBorrower() public {
        console2.log("onFlashLoan() reverts since initiator is not borrower(self)");

        vm.expectRevert("FlashBorrower: Untrusted loan initiator");
        vm.prank(address(vault));
        borrower.onFlashLoan(address(user), address(dai), 1000, 1, bytes("test"));
    }

    function testRevertOnFailedCallback() public {
        console2.log("onFlashLoan() reverts since it returns in incorrect keccak hash on callback");

        vm.expectRevert("IERC3156: Callback failed");
        failedBorrower.flashBorrow(address(dai), 100);
    }

    function testCannotBorrowExcess() public {
        console2.log("Borrower attempts to borrow exceeding max loan amount");
       
        uint maxLoan = vault.maxFlashLoan(address(dai));        
        vm.expectRevert("ERC20: Insufficient balance");
        borrower.flashBorrow(address(dai), maxLoan * 2);
    }

    function testMaxFlashLoan() public {
        console2.log("maxFlashLoan should return the DAI holdings of vault");
       
        uint maxLoan = vault.maxFlashLoan(address(dai));
        assertTrue(maxLoan == dai.balanceOf(address(vault)));
    }

    function testFlashLoan() public {
        console2.log("Borrower initiates flashloan");
       
        //Note: amount borrowed and starting DAI balance of borrower are equal: 100 * 1e18
        uint amount = 100 * 1e18;
        uint fee = amount * 1000 / 10000;
        uint vaultBalance = dai.balanceOf(address(vault));
        
        borrower.flashBorrow(address(dai), amount);
        
        //assert that fee has been accurately deducted from borrower
        assertTrue(dai.balanceOf(address(borrower)) == amount - fee);
        //assert that fee has been received by lender
        assertTrue(dai.balanceOf(address(vault)) == vaultBalance + fee);
    }


}

//Note: Exchange rate between shares and assets have changed, given income generated from fees.
abstract contract StateRateChanged is StateFlashLoan {
    
    function setUp() public override virtual {
        super.setUp();

        uint amount = 1000 * 1e18;
        uint fee = amount * 1000 / 10000;
        uint vaultBalance = dai.balanceOf(address(vault));
        
        borrower.flashBorrow(address(dai), amount);

    } 
} 

//Note: Previously, 1 wrapped minted per unit DAI deposited => wrappedMinted = Supply(wrapped) / Supply(underlying) = 1000/1000 = 1 
//      Fees accrued = 1000 * 0.1% = 1 DAI     
//      New ex_rate: Supply(wrapped) / Supply(underlying) = 1000/(1000+1) = 1000/1001 = 0.999000999000999...
//      For each unit of DAI deposited, 0.999000999000999... of wrapped tokens will be minted. 
contract StateRateChangedTest is StateRateChanged {
 
    // Regardless withdraw or redeem the same proportionality changes to wrapped and underlying tokens apply due to ex_rate changes
    function testCannotWithdrawOrRedeemSameAmount() public {
        console2.log("Rate depreciates: User's shares are convertible for more than original deposit sum");
        console2.log("1 yvDAI is convertible for more than 1 DAI");
        
        //Note: user deposited userTokens/2 worth of underlying before rate changed.
        uint assets = vault.maxWithdraw(user);
        assertTrue(assets > userTokens/2);
    }


    function testCannotDepositSameAmount() public {
        console2.log("Rate depreciates: User's second deposit converts to fewer shares than before");
        console2.log("1 DAI is convertible slightly less than 1 yvDAI");

        vm.prank(user);
        vault.deposit(userTokens/2, user);

        assertTrue(dai.balanceOf(user) == 0);
        assertTrue(vault.balanceOf(user) < userTokens);
    }

    function testWithdrawRateChange() public {
        console2.log("Rate depreciates: User withdraws his deposit of userTokens/2 | will have remainder shares");
        
        // initialShares == userTokens/2
        uint initialShares = vault.balanceOf(user);
        // to call convertToShares(userTokens/2)
        uint sharesWithdrawn = vault.previewDeposit(userTokens/2);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, userTokens/2, sharesWithdrawn);
        
        vm.prank(user);
        vault.withdraw(userTokens/2, user, user);
        
        // remainder of shares(wrapper tokens) in vault, on withdrawing initial deposit, indicative of rate depreciation
        assertTrue(vault.balanceOf(user) == initialShares - sharesWithdrawn);
        assertTrue(dai.balanceOf(user) == userTokens);
    }
    

    function testRedeemRateChange() public {
        console2.log("Rate depreciates: User redeems userTokens/2 worth of SHARES | will gain ASSETS of a larger quantity");
        console2.log("1 yvDAI is convertible for slightly more than 1 DAI");

        // @old ex_rate: user had userTokens/2 of shares and assets, in equal amounts
        // previewRedeem for accessing convertToAssets()
        uint maxShares = vault.maxRedeem(user);
        assertTrue(maxShares == userTokens/2);

        uint assets = vault.previewRedeem(maxShares);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, assets, maxShares);
        
        vm.prank(user);
        vault.redeem(maxShares, user, user);    

        // @new ex_rate: shares on redemption would convert to > userTokens/2
        assertTrue(vault.balanceOf(user) == 0);
        assertTrue(dai.balanceOf(user) > userTokens);
    }

}

