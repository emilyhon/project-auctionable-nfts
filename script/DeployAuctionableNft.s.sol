// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {AuctionableNft} from "../src/AuctionableNft.sol";

contract DeployAuctionableNft is Script {
    function run() external returns (AuctionableNft) {
        vm.startBroadcast();
        AuctionableNft auctionableNft = new AuctionableNft();
        vm.stopBroadcast();
        return auctionableNft;
    }
}
