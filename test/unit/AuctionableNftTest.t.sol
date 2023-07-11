// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AuctionableNft} from "../../src/AuctionableNft.sol";

contract AuctionableNftTest is Test {
    AuctionableNft auctionableNft;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        auctionableNft = new AuctionableNft();
        vm.deal(USER, STARTING_USER_BALANCE);
    }

    function testMintNft() public {
        uint256 price = auctionableNft.getMintPrice();
        vm.prank(USER);
        auctionableNft.mintNft{value: price}("");

        assertEq(auctionableNft.ownerOf(0), address(auctionableNft));

        (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp) = auctionableNft.getAuctionListing(0);
        assertEq(bidderAddr, address(USER));
        assertEq(bidAmount, price);
        assertEq(expiryTimestamp, block.timestamp + auctionableNft.getAuctionDurationInSeconds());
    }
}
