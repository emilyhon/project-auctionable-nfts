// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AuctionableNft} from "../../src/AuctionableNft.sol";

contract AuctionableNftTest is Test {
    AuctionableNft auctionableNft;

    address public USER = makeAddr("user");
    address public BIDDER = makeAddr("bidder");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        auctionableNft = new AuctionableNft();
        vm.deal(USER, STARTING_USER_BALANCE);
        vm.deal(BIDDER, STARTING_USER_BALANCE);
    }

    /////..... mintNft ...../////

    function testMintNftSuccess() public mintedNftWithUser {
        uint256 price = auctionableNft.getMintPrice();

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

    // TODO: Test mint nft token URI stored properly

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

    // TODO: Add test for checking the token URI or other parameters

    function testMintNftOverMintPrice() public {
        uint256 price = auctionableNft.getMintPrice();
        uint256 payment = price * 2;
        vm.prank(USER);
        auctionableNft.mintNft{value: payment}("");

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

        // Assert new auction listing is stored properly
        assertEq(auctionableNft.ownerOf(0), address(auctionableNft));
        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(BIDDER));
        assertEq(bidAmount, placedBidAmount);
        assertEq(expiryTimestamp, originalTimestamp + auctionableNft.getAuctionDurationInSeconds());

        // Assert previous bidder is eligible for fund withdrawal
        assertEq(auctionableNft.getPendingWithdrawalAmount(USER), mintPrice);
    }

    function testPlaceBidSuccessMultiple() public mintedNftWithUser {}

    function testPlaceBidSuccessWithSameBidderHigherAmount() public mintedNftWithUser {}

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

    /////..... withdrawInvalidBid ...../////
    /////..... onERC721Received ...../////
    /////..... checkUpkeep ...../////
    /////..... performUpkeep ...../////
    /////..... _processCompletedAuctionListing ...../////

    /////..... Modifiers ...../////
    modifier mintedNftWithUser() {
        uint256 price = auctionableNft.getMintPrice();
        vm.prank(USER);
        auctionableNft.mintNft{value: price}("");
        _;
    }
}
