// Invariants:
// 1. Wallet balance must be greater than pending withdrawals total
// 2. Bids must be higher than the previous bid or mint price if there's no previous bid
// 3. Users cannot withdraw more eth than they put in

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AuctionableNft} from "../../src/AuctionableNft.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract AuctionableNftTest is StdInvariant, Test {}
