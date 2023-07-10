// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract Spud is ERC721 {
    struct AuctionInfo {
        address addr;
        uint256 bidAmount;
        uint256 auctionEndTimestamp;
    }

    error Spud__UpkeepNotNeeded(AuctionInfo nextAuctionInfo);

    uint16 private constant MAX_NUM_TOKENS = 1000;
    uint32 private constant AUCTION_DURATION = 2 * 24 * 60 * 60; // 2 days

    uint16 private s_tokenCounter;
    uint16 private s_auctionTokenCounter;
    string[] s_tokenUris;
    AuctionInfo[] s_auctionInfos;

    constructor() ERC721("Spud", "SPUD") {}

    /**
     * Mint function that sends the NFT to this contract address and triggers the auction process of the NFT
     * @param tokenURI The token URI associated with this minted token
     */
    function mintNft(string memory tokenURI) external payable {
        // add check for amount
        // TODO: revert if over max mint amount
        _safeMint(address(this), s_tokenCounter);
        s_auctionInfos[s_tokenCounter] = AuctionInfo({
            addr: msg.sender,
            bidAmount: msg.value,
            auctionEndTimestamp: block.timestamp + AUCTION_DURATION
        });
        s_tokenUris[s_tokenCounter] = tokenURI;

        s_tokenCounter++;
    }

    function bidOnNft(uint256 tokenId) external {
        // store address and bid amount
        // refund last bidder
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call to see if it is time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time is past the end timestamp of the oldest token on auction
     * 2. There are still NFTs in the auction state
     * 3. The contract has ETH for the performUpkeep function
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpkeep(bytes memory /*checkData*/ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /*performData */ )
    {
        bool timeHasPassed = block.timestamp >= s_auctionInfos[s_auctionTokenCounter].auctionEndTimestamp;
        bool isAuctionActive = s_auctionTokenCounter != MAX_NUM_TOKENS;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timeHasPassed && isAuctionActive && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Spud__UpkeepNotNeeded(s_auctionInfos[s_auctionTokenCounter]); // TODO: add params
        }

        // Transfer NFT to top bidder

        // Set auction token counter ++
    }
}
