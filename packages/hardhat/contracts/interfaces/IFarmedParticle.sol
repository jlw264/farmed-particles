// SPDX-License-Identifier: MIT

// Proton.sol -- Part of the Charged Particles Protocol
// Copyright (c) 2021 Firma Lux, Inc. <https://charged.fi>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IUniverse.sol";
import "../interfaces/IChargedState.sol";
import "../interfaces/IChargedSettings.sol";
import "../interfaces/IChargedParticles.sol";

import "../lib/BlackholePrevention.sol";
import "../lib/RelayRecipient.sol";


interface IFarmedParticle is IERC721 {
  event UniverseSet(address indexed universe);
  event ChargedStateSet(address indexed chargedState);
  event ChargedSettingsSet(address indexed chargedSettings);
  event ChargedParticlesSet(address indexed chargedParticles);
  event PausedStateSet(bool isPaused);
  event SalePriceSet(uint256 indexed tokenId, uint256 salePrice);
  event FeesWithdrawn(address indexed receiver, uint256 amount);
  event FieldSold(uint256 indexed tokenId, address indexed oldOwner, address indexed newOwner, uint256 salePrice);

  /***********************************|
  |              Public               |
  |__________________________________*/

  function creatorOf(uint256 tokenId) external view returns (address);
  function getSalePrice(uint256 tokenId) external view returns (uint256);
  function getLastSellPrice(uint256 tokenId) external view returns (uint256);
  function getCreatorAnnuityPercent() external view returns (uint256);

  function tokenURI2(uint256 tokenId) external returns (string memory);

  // modeled off of buyProton
  function buyField(uint256 tokenId) external payable returns (bool);

  // modeled off of createProton
  function createEmptyField(
    address receiver,
    string memory tokenMetaUri
  ) external returns (uint256 newTokenId);


  /***********************************|
  |     Only Token Creator/Owner      |
  |__________________________________*/

  function plantCrops(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken,
    uint256 assetAmount
  ) external;

  function harvest(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken
  ) external returns (uint256 creatorAmount, uint256 receiverAmount);

  function setSalePrice(uint256 tokenId, uint256 salePrice) external;
}