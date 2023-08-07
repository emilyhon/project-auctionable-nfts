// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AuctionableNft} from "../../src/AuctionableNft.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract AuctionableNftTest is Test {
    AuctionableNft auctionableNft;

    address public USER = makeAddr("user");
    address public BIDDER = makeAddr("bidder");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        auctionableNft = new AuctionableNft(address(this));
        vm.deal(USER, STARTING_USER_BALANCE);
        vm.deal(BIDDER, STARTING_USER_BALANCE);
    }

    receive() external payable {}

    /////..... mintNft ...../////

    function testMintNftSuccess() public mintedNftWithUser {
        uint256 price = auctionableNft.getMintPrice();

        assertEq(USER.balance, STARTING_USER_BALANCE - price);
        assertEq(address(auctionableNft).balance, price);

        assertEq(auctionableNft.ownerOf(0), address(auctionableNft));
        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(USER));
        assertEq(bidAmount, price);
        assertEq(expiryTimestamp, block.timestamp + auctionableNft.getAuctionDurationInSeconds());
    }

    function testMintNftSuccessMultiple() public mintedNftWithUser {
        uint256 price = auctionableNft.getMintPrice();

        assertEq(auctionableNft.ownerOf(0), address(auctionableNft));
        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(USER));
        assertEq(bidAmount, price);
        assertEq(expiryTimestamp, block.timestamp + auctionableNft.getAuctionDurationInSeconds());

        uint256 timePassed = 100;
        vm.warp(block.timestamp + timePassed);

        address user2 = makeAddr("user2");
        vm.deal(user2, price);
        vm.prank(user2);
        auctionableNft.mintNft{value: price}("");

        assertEq(auctionableNft.ownerOf(1), address(auctionableNft));
        (address bidderAddr2, uint256 bidAmount2, uint256 expiryTimestamp2) = auctionableNft.getAuctionListing(1);
        assertEq(bidderAddr2, address(user2));
        assertEq(bidAmount2, price);
        assertEq(expiryTimestamp2, block.timestamp + auctionableNft.getAuctionDurationInSeconds());

        assertEq(expiryTimestamp + timePassed, expiryTimestamp2);
    }

    function testMintNftTokenURI() public {
        string memory tokenURI = "hello";
        uint256 price = auctionableNft.getMintPrice();
        vm.prank(USER);
        auctionableNft.mintNft{value: price}(tokenURI);

        assertEq(tokenURI, auctionableNft.tokenURI(0));
    }

    function testMintNftNotEnoughFunds() public {
        vm.expectRevert(AuctionableNft.AuctionableNft__NotEnoughFunds.selector);
        vm.prank(USER);
        auctionableNft.mintNft{value: 0}("");
    }

    function testMintNftSoldOut() public {
        uint256 price = auctionableNft.getMintPrice();
        uint256 maxCollectionSize = auctionableNft.getMaxSupply();
        vm.deal(USER, price * (maxCollectionSize + 1));

        vm.startPrank(USER);
        for (uint256 i = 0; i < maxCollectionSize; i++) {
            auctionableNft.mintNft{value: price}("");
        }

        vm.expectRevert(AuctionableNft.AuctionableNft__CollectionSoldOut.selector);
        auctionableNft.mintNft{value: price}("");
        vm.stopPrank();
    }

    function testMintNftOverMintPrice() public {
        uint256 price = auctionableNft.getMintPrice();
        uint256 payment = price * 2;
        vm.prank(USER);
        auctionableNft.mintNft{value: payment}("");

        assertEq(USER.balance, STARTING_USER_BALANCE - payment);
        assertEq(address(auctionableNft).balance, payment);

        assertEq(auctionableNft.ownerOf(0), address(auctionableNft));
        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(USER));
        assertEq(bidAmount, payment);
        assertEq(expiryTimestamp, block.timestamp + auctionableNft.getAuctionDurationInSeconds());
    }

    /////..... placeBid ...../////

    function testPlaceBidSuccess() public mintedNftWithUser {
        // Warp time to ensure bidding does not change the auction expiry time
        uint256 originalTimestamp = block.timestamp;
        vm.warp(originalTimestamp + 100);

        uint256 mintPrice = auctionableNft.getMintPrice();
        uint256 minBidIncrement = auctionableNft.getMinimumBidIncrement();
        uint256 placedBidAmount = mintPrice + minBidIncrement;
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: placedBidAmount}(0);

        // Assert funds were transferred successfully
        assertEq(USER.balance, STARTING_USER_BALANCE - mintPrice);
        assertEq(BIDDER.balance, STARTING_USER_BALANCE - placedBidAmount);
        assertEq(address(auctionableNft).balance, mintPrice + placedBidAmount);

        // Assert new auction listing is stored properly
        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(BIDDER));
        assertEq(bidAmount, placedBidAmount);
        assertEq(expiryTimestamp, originalTimestamp + auctionableNft.getAuctionDurationInSeconds());

        // Assert previous bidder is eligible for fund withdrawal
        assertEq(auctionableNft.getPendingWithdrawalAmount(USER), mintPrice);
    }

    function testPlaceBidSuccessMultiple() public mintedNftWithUser {
        uint256 mintPrice = auctionableNft.getMintPrice();
        uint256 minBidIncrement = auctionableNft.getMinimumBidIncrement();
        uint256 placedBidAmount = mintPrice + minBidIncrement;
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: placedBidAmount}(0);

        address newBidder = makeAddr("newBidder");
        vm.deal(newBidder, STARTING_USER_BALANCE);
        vm.prank(newBidder);
        auctionableNft.placeBid{value: STARTING_USER_BALANCE}(0);

        // Assert new auction listing is stored properly
        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(newBidder));
        assertEq(bidAmount, STARTING_USER_BALANCE);
        assertEq(expiryTimestamp, block.timestamp + auctionableNft.getAuctionDurationInSeconds());

        // Assert previous bidders are eligible for fund withdrawal
        assertEq(auctionableNft.getPendingWithdrawalAmount(USER), mintPrice);
        assertEq(auctionableNft.getPendingWithdrawalAmount(BIDDER), placedBidAmount);
    }

    function testPlaceBidSuccessWithSameBidderHigherAmount() public mintedNftWithUser {
        uint256 mintPrice = auctionableNft.getMintPrice();
        uint256 minBidIncrement = auctionableNft.getMinimumBidIncrement();
        uint256 firstBidAmount = mintPrice + minBidIncrement;
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: firstBidAmount}(0);

        assertEq(BIDDER.balance, STARTING_USER_BALANCE - firstBidAmount);

        uint256 secondBidAmount = 10 ether;
        vm.deal(BIDDER, secondBidAmount);
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: secondBidAmount}(0);

        // Assert funds were transferred successfully
        assertEq(BIDDER.balance, 0);
        assertEq(address(auctionableNft).balance, mintPrice + firstBidAmount + secondBidAmount);

        // Assert new auction listing is stored properly
        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(BIDDER));
        assertEq(bidAmount, STARTING_USER_BALANCE);
        assertEq(expiryTimestamp, block.timestamp + auctionableNft.getAuctionDurationInSeconds());

        // Assert previous bidders are eligible for fund withdrawal
        assertEq(auctionableNft.getPendingWithdrawalAmount(USER), mintPrice);
        assertEq(auctionableNft.getPendingWithdrawalAmount(BIDDER), firstBidAmount);
    }

    function testPlaceBidFailOnUnmintedNft() public {
        vm.expectRevert(AuctionableNft.AuctionableNft__BiddingOnUnmintedNft.selector);
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: STARTING_USER_BALANCE}(0);
    }

    function testPlaceBidFailOnUnmetMinBidAmount() public mintedNftWithUser {
        uint256 minBidAmount = auctionableNft.getMintPrice() + auctionableNft.getMinimumBidIncrement();
        vm.expectRevert(
            abi.encodeWithSelector(AuctionableNft.AuctionableNft__BidAmountMustBeGreaterThan.selector, minBidAmount)
        );
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: minBidAmount - 1}(0);
    }

    function testPlaceBidFailOnExpiredAuction() public mintedNftWithUser {
        uint256 minBidIncrement = auctionableNft.getMinimumBidIncrement();
        uint256 minBidAmount = auctionableNft.getMintPrice() + minBidIncrement;

        uint256 mintTimestamp = block.timestamp;
        uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();

        // Bidder should be able to place bid on the expiry timestamp
        vm.warp(expiryTimestamp);
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: minBidAmount}(0);

        // Bidder should not be able to place bid past the expiry timestamp
        vm.warp(expiryTimestamp + 1);
        vm.expectRevert(AuctionableNft.AuctionableNft__AuctionExpired.selector);
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: minBidAmount + minBidIncrement}(0);
    }

    /////..... withdrawBalance ...../////

    function testWithdrawBalanceSuccessForMinter() public mintedNftWithUser bidOnToken0WithBidder {
        assertEq(auctionableNft.getMintPrice(), auctionableNft.getPendingWithdrawalAmount(USER));
    }

    function testWithdrawBalanceSuccessForBidder() public mintedNftWithUser {
        uint256 minBidAmount = auctionableNft.getMinimumBidAmount(0);
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: minBidAmount}(0);

        address newBidder = makeAddr("newBidder");
        uint256 newBidAmount = 10 ether;
        vm.deal(newBidder, newBidAmount);
        vm.prank(newBidder);
        auctionableNft.placeBid{value: newBidAmount}(0);

        uint256 expectedWithdrawalAmount = auctionableNft.getPendingWithdrawalAmount(BIDDER);
        assertEq(expectedWithdrawalAmount, minBidAmount);

        uint256 bidderBeginningBalance = BIDDER.balance;
        uint256 contractBeginningBalance = address(auctionableNft).balance;
        vm.prank(BIDDER);
        auctionableNft.withdrawBalance();

        assertEq(auctionableNft.getPendingWithdrawalAmount(BIDDER), 0);
        assertEq(BIDDER.balance, bidderBeginningBalance + expectedWithdrawalAmount);
        assertEq(address(auctionableNft).balance, contractBeginningBalance - expectedWithdrawalAmount);
    }

    function testWithdrawBalanceSuccessNoBalance() public mintedNftWithUser {
        uint256 userBalance = USER.balance;
        vm.prank(USER);
        auctionableNft.withdrawBalance();
        assertEq(userBalance, USER.balance);
    }

    /////..... withdraw ...../////

    function testWithdrawSuccess() public mintedNftWithUser bidOnToken0WithBidder {
        uint256 mintTimestamp = block.timestamp;
        uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();
        vm.warp(expiryTimestamp + 1);

        // Owner should be able to withdraw amount equal to the bid amount
        uint256 initialBalance = address(this).balance;
        uint256 lastBidAmount = auctionableNft.getLastBidAmount(0);
        auctionableNft.withdraw(lastBidAmount);
        assertEq(address(this).balance, initialBalance + lastBidAmount);
    }

    function testWithdrawFailNonOwner() public {
        vm.expectRevert();
        vm.prank(USER);
        auctionableNft.withdraw(0);
    }

    function testWithdrawFailExceedingAmount() public {
        vm.expectRevert(AuctionableNft.AuctionableNft__ExceededWithdrawalLimit.selector);
        auctionableNft.withdraw(1);
    }

    function testWithdrawZero() public {
        auctionableNft.withdraw(0);
    }

    /////..... onERC721Received ...../////

    function testOnERC721Received() public {
        bytes4 expectedReturn = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
        assertEq(expectedReturn, auctionableNft.onERC721Received(USER, USER, 0, ""));
    }

    /////..... checkUpkeep ...../////

    function testCheckUpkeepTrue() public mintedNftWithUser {
        // pass time
        uint256 mintTimestamp = block.timestamp;
        uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();
        vm.warp(expiryTimestamp + 1);

        (bool upkeepNeeded,) = auctionableNft.checkUpkeep("0x0");
        assertEq(upkeepNeeded, true);
    }

    function testCheckUpkeepFalseNoActiveAuction() public {
        (bool upkeepNeeded,) = auctionableNft.checkUpkeep("0x0");
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepFalseTimeNotPassed() public mintedNftWithUser {
        // pass time
        uint256 mintTimestamp = block.timestamp;
        uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();
        vm.warp(expiryTimestamp - 1);
        (bool upkeepNeeded,) = auctionableNft.checkUpkeep("0x0");
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepFalseAllAuctionedAlready() public {
        uint256 price = auctionableNft.getMintPrice();
        uint256 numSupply = auctionableNft.getMaxSupply();
        vm.deal(USER, price * numSupply);

        for (uint256 i = 0; i < numSupply; i++) {
            vm.prank(USER);
            auctionableNft.mintNft{value: price}("");

            uint256 mintTimestamp = block.timestamp;
            uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();
            vm.warp(expiryTimestamp + 1);

            (bool upkeepNeeded,) = auctionableNft.checkUpkeep("0x0");
            assertEq(upkeepNeeded, true);
        }

        vm.warp(block.timestamp * 2);

        (bool finalUpkeepNeeded,) = auctionableNft.checkUpkeep("0x0");
        assertEq(finalUpkeepNeeded, true);
    }

    /////..... performUpkeep ...../////
    /////..... _processCompletedAuctionListing ...../////

    function testPerformUpkeepSuccess() public mintedNftWithUser {
        // pass time
        uint256 mintTimestamp = block.timestamp;
        uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();
        vm.warp(expiryTimestamp + 1);

        auctionableNft.performUpkeep("");
        assertEq(auctionableNft.getAuctionTokenCounter(), 1);
        assertEq(auctionableNft.ownerOf(0), address(USER));
    }

    function testPerformUpkeepFailsUpkeepNotNeeded() public mintedNftWithUser {
        vm.expectRevert(AuctionableNft.AuctionableNft__UpkeepNotNeeded.selector);
        auctionableNft.performUpkeep("");
    }

    /////..... public view / pure functions ...../////

    function testGetMinimumBidAmountReturnsMaxIntOnInvalidListing() public {
        uint256 maxInt = 2 ** 256 - 1;
        assertEq(maxInt, auctionableNft.getMinimumBidAmount(0));
    }

    function testGetNumMintedTokens() public {
        assertEq(0, auctionableNft.getNumMintedTokens());

        uint256 price = auctionableNft.getMintPrice();
        vm.prank(USER);
        auctionableNft.mintNft{value: price}("");

        assertEq(1, auctionableNft.getNumMintedTokens());
    }

    function testGetWithdrawableAmounts() public mintedNftWithUser {
        // pass time
        uint256 mintTimestamp = block.timestamp;
        uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();
        vm.warp(expiryTimestamp + 1);

        assertEq(auctionableNft.getPendingWithdrawalTotal(), 0);
        assertEq(auctionableNft.getMintPrice(), auctionableNft.getMaxWithdrawableAmount());
    }

    function testGetMaxWithdrawableAmount() public mintedNftWithUser {
        uint256 minBidAmount = auctionableNft.getMinimumBidAmount(0);
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: minBidAmount}(0);

        uint256 mintPrice = auctionableNft.getMintPrice();
        assertEq(auctionableNft.getPendingWithdrawalTotal(), mintPrice);
        assertEq(auctionableNft.getPendingWithdrawalAmount(address(USER)), mintPrice);

        // pass time
        uint256 mintTimestamp = block.timestamp;
        uint256 expiryTimestamp = mintTimestamp + auctionableNft.getAuctionDurationInSeconds();
        vm.warp(expiryTimestamp + 1);

        assertEq(auctionableNft.getPendingWithdrawalTotal(), mintPrice);
        assertEq(minBidAmount, auctionableNft.getMaxWithdrawableAmount());
    }

    /////..... Modifiers ...../////
    modifier mintedNftWithUser() {
        uint256 price = auctionableNft.getMintPrice();
        vm.prank(USER);
        auctionableNft.mintNft{value: price}("");
        _;
    }

    modifier bidOnToken0WithBidder() {
        uint256 minBidAmount = auctionableNft.getMinimumBidAmount(0);
        vm.prank(BIDDER);
        auctionableNft.placeBid{value: minBidAmount}(0);
        _;
    }
}
