pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;
//SPDX-License-Identifier: MIT

import "./lib/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IFarmedParticle.sol";
import "./interfaces/IUniverse.sol";
import "./interfaces/IChargedState.sol";
import "./interfaces/IChargedSettings.sol";
import "./interfaces/IChargedParticles.sol";

import "./lib/BlackholePrevention.sol";
import "./lib/RelayRecipient.sol";

contract FarmedParticle is IFarmedParticle, ERC721, Ownable, RelayRecipient, ReentrancyGuard, BlackholePrevention {

  using SafeMath for uint256;
  using Address for address payable;
  using Counters for Counters.Counter;

  IUniverse internal _universe;
  IChargedState internal _chargedState;
  IChargedSettings internal _chargedSettings;
  IChargedParticles internal _chargedParticles;

  Counters.Counter internal _tokenIds;

  address internal _farmCreator;
  uint256 internal _farmCreatorAnnuityPercent;

  mapping (uint256 => uint256) internal _tokenSalePrice;
  mapping (uint256 => uint256) internal _tokenLastSellPrice;

  bool internal _paused;


  /***********************************|
  |          Initialization           |
  |__________________________________*/

  constructor(address farmCreator, uint256 farmCreatorAnnuityPercent) public ERC721("Farmed Particles", "FARMED") {
    _farmCreator = farmCreator;
    _farmCreatorAnnuityPercent = farmCreatorAnnuityPercent;
  }


  /***********************************|
  |              Public               |
  |__________________________________*/

  function creatorOf(uint256 tokenId) external view virtual override returns (address) {
    return _farmCreator;
  }

  function getSalePrice(uint256 tokenId) external view virtual override returns (uint256) {
    return _tokenSalePrice[tokenId];
  }

  function getLastSellPrice(uint256 tokenId) external view virtual override returns (uint256) {
    return _tokenLastSellPrice[tokenId];
  }

  function getCreatorAnnuityPercent() external view virtual override returns (uint256) {
    return _farmCreatorAnnuityPercent;
  }

  function createEmptyField(
    address receiver,
    string memory tokenMetaUri
  )
    external
    virtual
    override
    whenNotPaused
    returns (uint256 newTokenId)
  {
    newTokenId = _createEmptyField(
      _farmCreator,
      receiver,
      tokenMetaUri,
      _farmCreatorAnnuityPercent
    );
  }

  function buyField(uint256 tokenId)
    external
    payable
    virtual
    override
    nonReentrant
    whenNotPaused
    returns (bool)
  {
    return _buyField(tokenId);
  }

  /***********************************|
  |     Only Token Creator/Owner      |
  |__________________________________*/

  function plantCrops(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken,
    uint256 assetAmount
  ) 
    external
    virtual
    override
    nonReentrant
    whenNotPaused
  {
    return _plantCrops(
      tokenId,
      walletManagerId,
      assetToken,
      assetAmount
    );
  }

  function setSalePrice(uint256 tokenId, uint256 salePrice)
    external
    virtual
    override
    whenNotPaused
    onlyTokenOwnerOrApproved(tokenId)
  {
    _setSalePrice(tokenId, salePrice);
  }


  /***********************************|
  |          Only Admin/DAO           |
  |__________________________________*/

  function setPausedState(bool state) external virtual onlyOwner {
    _paused = state;
    emit PausedStateSet(state);
  }

  /**
    * @dev Setup the ChargedParticles Interface
    */
  function setUniverse(address universe) external virtual onlyOwner {
    _universe = IUniverse(universe);
    emit UniverseSet(universe);
  }

  /**
    * @dev Setup the ChargedParticles Interface
    */
  function setChargedParticles(address chargedParticles) external virtual onlyOwner {
    _chargedParticles = IChargedParticles(chargedParticles);
    emit ChargedParticlesSet(chargedParticles);
  }

  /// @dev Setup the Charged-State Controller
  function setChargedState(address stateController) external virtual onlyOwner {
    _chargedState = IChargedState(stateController);
    emit ChargedStateSet(stateController);
  }

  /// @dev Setup the Charged-Settings Controller
  function setChargedSettings(address settings) external virtual onlyOwner {
    _chargedSettings = IChargedSettings(settings);
    emit ChargedSettingsSet(settings);
  }

  /***********************************|
  |          Only Admin/DAO           |
  |      (blackhole prevention)       |
  |__________________________________*/

  function withdrawEther(address payable receiver, uint256 amount) external onlyOwner {
    _withdrawEther(receiver, amount);
  }

  function withdrawErc20(address payable receiver, address tokenAddress, uint256 amount) external onlyOwner {
    _withdrawERC20(receiver, tokenAddress, amount);
  }

  function withdrawERC721(address payable receiver, address tokenAddress, uint256 tokenId) external onlyOwner {
    _withdrawERC721(receiver, tokenAddress, tokenId);
  }


  /***********************************|
  |         Private Functions         |
  |__________________________________*/

  function _setSalePrice(uint256 tokenId, uint256 salePrice) internal virtual {
    // Temp-Lock/Unlock NFT
    //  prevents front-running the sale and draining the value of the NFT just before sale
    _chargedState.setTemporaryLock(address(this), tokenId, (salePrice > 0));

    _tokenSalePrice[tokenId] = salePrice;
    emit SalePriceSet(tokenId, salePrice);
  }

  function _createEmptyField(
    address creator,
    address receiver,
    string memory tokenMetaUri,
    uint256 annuityPercent
  )
    internal
    virtual
    returns (uint256 newTokenId)
  {
    require(address(_chargedSettings) != address(0x0), "PRT:E-107");

    _tokenIds.increment();

    newTokenId = _tokenIds.current();
    _safeMint(receiver, newTokenId, "");

    _setTokenURI(newTokenId, tokenMetaUri);  // TODO

    if (annuityPercent > 0) {
      _chargedSettings.setCreatorAnnuities(
        address(this),
        newTokenId,
        creator,
        annuityPercent
      );
    }
  }

  function _plantCrops(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken,
    uint256 assetAmount
  )
    internal
    virtual
  {
    require(address(_chargedParticles) != address(0x0), "PRT:E-107");

    _chargeParticle(tokenId, walletManagerId, assetToken, assetAmount);
  }

  function _chargeParticle(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken,
    uint256 assetAmount
  )
    internal
    virtual
  {
    _collectAssetToken(_msgSender(), assetToken, assetAmount);

    IERC20(assetToken).approve(address(_chargedParticles), assetAmount);

    _chargedParticles.energizeParticle(
      address(this),
      tokenId,
      walletManagerId,
      assetToken,
      assetAmount,
      address(0)  // blackhole
    );
  }

  function _buyField(uint256 tokenId)
    internal
    virtual
    returns (bool)
  {
    uint256 salePrice = _tokenSalePrice[tokenId];
    require(salePrice > 0, "PRT:E-416");
    require(msg.value >= salePrice, "PRT:E-414");

    uint256 ownerAmount = salePrice;
    address oldOwner = ownerOf(tokenId);
    address newOwner = _msgSender();

    _tokenLastSellPrice[tokenId] = salePrice;

    // Transfer Token
    _transfer(oldOwner, newOwner, tokenId);

    // Transfer Payment
    payable(oldOwner).sendValue(ownerAmount);

    emit FieldSold(tokenId, oldOwner, newOwner, salePrice);

    _refundOverpayment(salePrice);
    return true;
  }

  /**
    * @dev Collects the Required Asset Token from the users wallet
    * @param from         The owner address to collect the Assets from
    * @param assetAmount  The Amount of Asset Tokens to Collect
    */
  function _collectAssetToken(address from, address assetToken, uint256 assetAmount) internal virtual {
    uint256 _userAssetBalance = IERC20(assetToken).balanceOf(from);
    require(assetAmount <= _userAssetBalance, "PRT:E-411");
    // Be sure to Approve this Contract to transfer your Asset Token
    require(IERC20(assetToken).transferFrom(from, address(this), assetAmount), "PRT:E-401");
  }

  function _refundOverpayment(uint256 threshold) internal virtual {
    uint256 overage = msg.value.sub(threshold);
    if (overage > 0) {
      payable(_msgSender()).sendValue(overage);
    }
  }

  function _transfer(address from, address to, uint256 tokenId) internal virtual override {
    _tokenSalePrice[tokenId] = 0;
    _chargedState.setTemporaryLock(address(this), tokenId, false);
    super._transfer(from, to, tokenId);
  }


  /***********************************|
  |          GSN/MetaTx Relay         |
  |__________________________________*/

  /// @dev See {BaseRelayRecipient-_msgSender}.
  function _msgSender()
    internal
    view
    virtual
    override(BaseRelayRecipient, Context)
    returns (address payable)
  {
    return BaseRelayRecipient._msgSender();
  }

  /// @dev See {BaseRelayRecipient-_msgData}.
  function _msgData()
    internal
    view
    virtual
    override(BaseRelayRecipient, Context)
    returns (bytes memory)
  {
    return BaseRelayRecipient._msgData();
  }


  /***********************************|
  |             Modifiers             |
  |__________________________________*/

  modifier whenNotPaused() {
      require(!_paused, "PRT:E-101");
      _;
  }

  modifier onlyTokenOwnerOrApproved(uint256 tokenId) {
    require(_isApprovedOrOwner(_msgSender(), tokenId), "PRT:E-105");
    _;
  }

  modifier onlyTokenCreator(uint256 tokenId) {
    require(_farmCreator == _msgSender(), "PRT:E-104");
    _;
  }

}