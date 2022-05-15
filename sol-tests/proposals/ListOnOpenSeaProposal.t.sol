// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./TestableListOnOpenSeaProposal.sol";

contract ListOnOpenSeaProposalTest is Test, TestUtils {
    uint256 constant ZORA_LISTING_DURATION = 60 * 60 * 24;
    TestableListOnOpenSeaProposal impl;
    Globals globals;
    SharedWyvernV2Maker sharedMaker;
    IWyvernExchangeV2 OS =
        IWyvernExchangeV2(0x7f268357A8c2552623316e2562D90e642bB538E5);
    IZoraAuctionHouse ZORA =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    DummyERC721 preciousToken;
    uint256 preciousTokenId;

    function setUp() public onlyForked {
        globals = new Globals(address(this));
        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION,
            ZORA_LISTING_DURATION
        );
        preciousToken = new DummyERC721();
        preciousTokenId = preciousToken.mint(address(this));
        sharedMaker = new SharedWyvernV2Maker(OS);
        impl = new TestableListOnOpenSeaProposal(
            globals,
            sharedMaker,
            ZORA
        );
        preciousToken.transferFrom(address(this), address(impl), preciousTokenId);
    }

    function _createTestProposal()
        private
        view
        returns (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        )
    {
        proposalData =
            ListOnOpenSeaProposal.OpenSeaProposalData({
                listPrice: 1e18,
                durationInSeconds: uint40(ZORA_LISTING_DURATION * 7)
            });
        executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomBytes32(),
                proposalData: abi.encode(proposalData),
                progressData: "",
                flags: 0,
                preciousToken: preciousToken,
                preciousTokenId: preciousTokenId
            });
    }

    // Test complete proposal execution steps, with all listings
    // expiring.
    function testForkedExecution_AllExpiring() public onlyForked {
        (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal();
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length != 0);
        {
            (
                ListOnOpenSeaProposal.OpenSeaStep step,
                ListOnZoraProposal.ZoraProgressData memory progressData
            ) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                ListOnZoraProposal.ZoraProgressData
            ));
            assertTrue(step == ListOnOpenSeaProposal.OpenSeaStep.ListedOnZora);
            assertTrue(progressData.auctionId != 0);
            assertTrue(progressData.minExpiry == block.timestamp + ZORA_LISTING_DURATION);
        }
        // Precious should be held by zora.
        assertTrue(preciousToken.ownerOf(preciousTokenId) == address(ZORA));
        // Expire the zora listing.
        skip(ZORA_LISTING_DURATION);
        // Next, retrieve from zora and list on OS.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length != 0);
        {
            (
                ListOnOpenSeaProposal.OpenSeaStep step,
                bytes32 orderHash,
                uint256 expiry
            ) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                bytes32,
                uint256
            ));
            assertTrue(step == ListOnOpenSeaProposal.OpenSeaStep.ListedOnOpenSea);
            assertTrue(orderHash != bytes32(0));
            assertTrue(expiry == block.timestamp + proposalData.durationInSeconds);
        }
        // Precious should be held by the shared wyvern sharedMaker.
        assertTrue(preciousToken.ownerOf(preciousTokenId) == address(sharedMaker));
        // Expire the OS listing.
        skip(proposalData.durationInSeconds);
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length == 0);
        // Done
    }

    // Test complete proposal execution steps, with unanimous votes, all listings
    // expiring.
    function testForkedExecution_UnanimousVote_AllExpiring() public onlyForked {
        (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal();
        executeParams.flags |= LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // This will list straight on OS because it was a unanmous vote.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length != 0);
        {
            (
                ListOnOpenSeaProposal.OpenSeaStep step,
                bytes32 orderHash,
                uint256 expiry
            ) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                bytes32,
                uint256
            ));
            assertTrue(step == ListOnOpenSeaProposal.OpenSeaStep.ListedOnOpenSea);
            assertTrue(orderHash != bytes32(0));
            assertTrue(expiry == block.timestamp + proposalData.durationInSeconds);
        }
        // Precious should be held by the shared wyvern sharedMaker.
        assertTrue(preciousToken.ownerOf(preciousTokenId) == address(sharedMaker));
        // Expire the OS listing.
        skip(proposalData.durationInSeconds);
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length == 0);
        // Done
    }
}
