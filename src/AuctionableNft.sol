// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

/**
 * @title A collection of NFTs that have a unique auction mechanic.
 * @author Emily Hon
 * @notice Any NFTs minted in this collection are minted to this contract address and are auctionable for a specified auction period. Afterwards, the NFT is transferred to the highest bidder or back to the original minter if no one bids.
 */
contract AuctionableNft is ERC721, AutomationCompatibleInterface, Ownable, IERC721Receiver {
    /// @dev Information related to an auction listing
    struct AuctionListing {
        address bidderAddr;
        uint256 bidAmount;
        uint256 expiryTimestamp;
    }

    event BidIncreased(uint256 tokenId, address bidder, uint256 amount);
    event AuctionEnded(uint256 tokenId, address highestBidder);

    error AuctionableNft__UpkeepNotNeeded();
    error AuctionableNft__NotEnoughFunds();
    error AuctionableNft__CollectionSoldOut();
    error AuctionableNft__BiddingOnUnmintedNft();
    error AuctionableNft__BidAmountMustBeGreaterThan(uint256 lastBidAmount);
    error AuctionableNft__AuctionExpired();
    error AuctionableNft__WithdrawalFailed();
    error AuctionableNft__ExceededWithdrawalLimit();

    uint256 private constant MAX_INT = 2 ** 256 - 1;
    uint256 private constant MAX_NUM_TOKENS = 1000;
    uint256 private constant MINT_PRICE = 0.1 ether;
    uint256 private constant MIN_BID_INCREMENT = 0.01 ether;
    uint256 private constant AUCTION_DURATION = 2 * 24 * 60 * 60; // 2 days
    bytes4 private constant ONERC721RECEIVED_EVENT_SIGNATURE = 0x150b7a02; // The 'onERC721Received' event signature is given by keccak256("onERC721Received(address,address,uint256,bytes)")

    uint256 private s_tokenCounter;
    uint256 private s_auctionTokenCounter;
    string[MAX_NUM_TOKENS] s_tokenUris;
    AuctionListing[MAX_NUM_TOKENS] s_auctionListings;
    mapping(address => uint256) s_pendingWithdrawals;
    uint256 s_pendingWithdrawalsTotal;

    /**
     * Instantiate the contract
     * @param initialOwner The address of the owner of this contract
     */
    constructor(address initialOwner, string memory name, string memory symbol)
        ERC721(name, symbol)
        Ownable(initialOwner)
    {}

    /**
     * Deposit ether
     */
    receive() external payable {
        // Maybe mintNft with random tokenURI
    }

    /**
     * Mint function that sends the NFT to this contract address and triggers the auction process of the NFT
     * @param tokenUri The token URI associated with this minted token
     */
    function mintNft(string memory tokenUri) external payable {
        if (msg.value < MINT_PRICE) {
            revert AuctionableNft__NotEnoughFunds();
        }
        if (s_tokenCounter >= MAX_NUM_TOKENS) {
            revert AuctionableNft__CollectionSoldOut();
        }

        // TODO: Add check to restrict the tokenURI passed in

        _safeMint(address(this), s_tokenCounter);
        s_auctionListings[s_tokenCounter] = AuctionListing({
            bidderAddr: msg.sender,
            bidAmount: msg.value,
            expiryTimestamp: block.timestamp + AUCTION_DURATION
        });
        s_tokenUris[s_tokenCounter] = tokenUri;

        s_tokenCounter++;
    }

    /**
     * Bid function that allows the caller to transfer funds and place a bid on an NFT
     * @param tokenId The tokenId the caller is bidding on
     * @notice This function allows the current highest bidder to bid on the same NFT so they can increase their bid
     * @dev When a bid is placed, the bid amount is transferred to this contract and the address of this bidder is stored. The previous bidder (or the original minter) will be able to withdraw their original bid by calling the withdrawInvalidBid() function
     */
    function placeBid(uint256 tokenId) external payable {
        AuctionListing memory listing = s_auctionListings[tokenId];
        if (listing.bidderAddr == address(0)) {
            revert AuctionableNft__BiddingOnUnmintedNft();
        }
        uint256 minBidAmount = listing.bidAmount + MIN_BID_INCREMENT;
        if (msg.value < minBidAmount) {
            revert AuctionableNft__BidAmountMustBeGreaterThan(minBidAmount);
        }
        if (block.timestamp > listing.expiryTimestamp) {
            revert AuctionableNft__AuctionExpired();
        }

        s_pendingWithdrawals[listing.bidderAddr] += listing.bidAmount;
        s_pendingWithdrawalsTotal += listing.bidAmount;

        s_auctionListings[tokenId] =
            AuctionListing({bidderAddr: msg.sender, bidAmount: msg.value, expiryTimestamp: listing.expiryTimestamp});

        emit BidIncreased(tokenId, msg.sender, msg.value);
    }

    /**
     * Withdraw function that allows caller to collect all their funds from invalid bids
     */
    function withdrawBalance() external {
        uint256 amount = s_pendingWithdrawals[msg.sender];
        delete s_pendingWithdrawals[msg.sender];
        s_pendingWithdrawalsTotal -= amount;
        (bool sent, /*bytes memory data*/ ) = msg.sender.call{value: amount}("");
        if (!sent) {
            revert AuctionableNft__WithdrawalFailed();
        }
    }

    /**
     * Withdraw function that allows the owner to withdraw the specified amount of funds from this contract
     * @param amount The amount to be withdrawn
     */
    function withdraw(uint256 amount) external onlyOwner {
        if (amount > getMaxWithdrawableAmount()) {
            revert AuctionableNft__ExceededWithdrawalLimit();
        }
        (bool sent, /*bytes memory data*/ ) = payable(owner()).call{value: amount}("");
        if (!sent) {
            revert AuctionableNft__WithdrawalFailed();
        }
    }

    /**
     * @inheritdoc IERC721Receiver
     */
    function onERC721Received(address, /*operator*/ address, /*from*/ uint256, /*tokenId*/ bytes calldata /*data*/ )
        external
        pure
        returns (bytes4)
    {
        return ONERC721RECEIVED_EVENT_SIGNATURE;
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
        if (s_auctionTokenCounter < MAX_NUM_TOKENS) {
            AuctionListing memory currentListing = s_auctionListings[s_auctionTokenCounter];
            bool isAuctionActive = currentListing.bidAmount > 0;
            bool timeHasPassed = block.timestamp >= currentListing.expiryTimestamp;
            bool hasBalance = address(this).balance > 0;
            upkeepNeeded = (timeHasPassed && isAuctionActive && hasBalance);
        }

        return (upkeepNeeded, "0x0");
    }

    /**
     * @dev This is the function that Chainlink Automation nodes call after checkUpkeep() returns true.
     * The function ends the expired auction of an NFT and transfers it to the highest bidder.
     */
    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert AuctionableNft__UpkeepNotNeeded();
        }

        uint256 tokenId = s_auctionTokenCounter;
        AuctionListing memory auctionListing = s_auctionListings[tokenId];
        address bidderAddr = auctionListing.bidderAddr;
        ERC721(address(this)).safeTransferFrom(address(this), bidderAddr, tokenId);

        s_auctionTokenCounter++;

        emit AuctionEnded(tokenId, bidderAddr);
    }

    /// Public view / pure functions
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return s_tokenUris[tokenId];
    }

    function getMaxSupply() public pure returns (uint256) {
        return MAX_NUM_TOKENS;
    }

    function getMintPrice() public pure returns (uint256) {
        return MINT_PRICE;
    }

    function getMinimumBidIncrement() public pure returns (uint256) {
        return MIN_BID_INCREMENT;
    }

    function getLastBidAmount(uint256 tokenId) public view returns (uint256) {
        AuctionListing storage listing = s_auctionListings[tokenId];
        return listing.bidAmount;
    }

    function getMinimumBidAmount(uint256 tokenId) public view returns (uint256) {
        AuctionListing storage listing = s_auctionListings[tokenId];
        uint256 lastBidAmount = listing.bidAmount;
        if (lastBidAmount == 0 || listing.expiryTimestamp < block.timestamp) {
            return MAX_INT;
        }

        return lastBidAmount + MIN_BID_INCREMENT;
    }

    function getAuctionDurationInSeconds() public pure returns (uint256) {
        return AUCTION_DURATION;
    }

    function getNumMintedTokens() public view returns (uint256) {
        return s_tokenCounter;
    }

    function getAuctionTokenCounter() public view returns (uint256) {
        return s_auctionTokenCounter;
    }

    function getAuctionListing(uint256 tokenId)
        public
        view
        returns (address bidderAddr, uint256 bidAmount, uint256 expiryTimestamp)
    {
        AuctionListing memory listing = s_auctionListings[tokenId];
        return (listing.bidderAddr, listing.bidAmount, listing.expiryTimestamp);
    }

    function getMaxWithdrawableAmount() public view returns (uint256) {
        return address(this).balance - s_pendingWithdrawalsTotal;
    }

    function getPendingWithdrawalAmount(address user) public view returns (uint256) {
        return s_pendingWithdrawals[user];
    }

    function getPendingWithdrawalTotal() public view onlyOwner returns (uint256) {
        return s_pendingWithdrawalsTotal;
    }
}
