pragma solidity 0.6.12;
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

  uint256 internal _fullHarvestThreshold = 2;
  uint256 internal _halfHarvestThreshold = 1;

  enum Status {
    Empty,
    Planted,
    HalfDai,
    HalfUni,
    HalfUsdc,
    FullDai,
    FullUni,
    FullUsdc
  }

  IUniverse internal _universe;
  IChargedState internal _chargedState;
  IChargedSettings internal _chargedSettings;
  IChargedParticles internal _chargedParticles;

  Counters.Counter internal _tokenIds;

  address internal _farmCreator;
  uint256 internal _farmCreatorAnnuityPercent;

  mapping (uint256 => uint256) internal _tokenSalePrice;
  mapping (uint256 => uint256) internal _tokenLastSellPrice;
  
  mapping (uint256 => address) internal _tokenIdToTokenAddress;
  mapping (string => address) internal _assetSymbolToAssetToken;
  mapping (Status => string) internal _statusToTokenURI;

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

  function getFullHarvestThreshold() external view virtual returns (uint256) {
    return _fullHarvestThreshold;
  }

  function getHalfHarvestThreshold() external view virtual returns (uint256) {
    return _halfHarvestThreshold;
  }

  // TODO - figure out how to make TokenURI dynamic
  // function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
  //   require(_exists(tokenId), "ERC721:E-405");
  //   Status tokenStatus = getStatus(tokenId);
  //   return _statusToTokenURI[tokenStatus];
  // }

  function tokenURI2(uint256 tokenId) external virtual override returns (string memory) {
    require(_exists(tokenId), "ERC721:E-405");
    Status tokenStatus = getStatus(tokenId);
    return _statusToTokenURI[tokenStatus];
  }

  function getParticleMassAaveDai(uint256 tokenId) public virtual returns (uint256) {
    return _getBaseParticleMass(
      _tokenIdToTokenAddress[tokenId], 
      tokenId, 
      "aave", 
      _assetSymbolToAssetToken["dai"]
    );
  }

  function getParticleMassAaveUni(uint256 tokenId) public virtual returns (uint256) {
    return _getBaseParticleMass(
      _tokenIdToTokenAddress[tokenId], 
      tokenId, 
      "aave", 
      _assetSymbolToAssetToken["uni"]
    );
  }

  function getParticleMassAaveUsdc(uint256 tokenId) public virtual returns (uint256) {
    return _getBaseParticleMass(
      _tokenIdToTokenAddress[tokenId], 
      tokenId, 
      "aave", 
      _assetSymbolToAssetToken["usdc"]
    );
  }

  function getChargeAaveDai(uint256 tokenId) public virtual returns (uint256) {
    return _getCurrentParticleCharge(
      _tokenIdToTokenAddress[tokenId], 
      tokenId, 
      "aave", 
      _assetSymbolToAssetToken["dai"]
    );
  }

  function getChargeAaveUni(uint256 tokenId) public virtual returns (uint256) {
    return _getCurrentParticleCharge(
      _tokenIdToTokenAddress[tokenId], 
      tokenId, 
      "aave", 
      _assetSymbolToAssetToken["uni"]
    );
  }

  function getChargeAaveUsdc(uint256 tokenId) public virtual returns (uint256) {
    return _getCurrentParticleCharge(
      _tokenIdToTokenAddress[tokenId], 
      tokenId, 
      "aave", 
      _assetSymbolToAssetToken["usdc"]
    );
  }

  function getStatus(uint256 tokenId) public virtual returns (Status) {
    uint256 baseDai = getParticleMassAaveDai(tokenId);
    uint256 baseUni = getParticleMassAaveUni(tokenId);
    uint256 baseUsdc = getParticleMassAaveUsdc(tokenId);

    if ((baseDai + baseUni + baseUsdc) == 0) {
      return Status.Empty;
    }

    uint256 chargeDai = getChargeAaveDai(tokenId);
    uint256 chargeUni = getChargeAaveUni(tokenId);
    uint256 chargeUsdc = getChargeAaveUsdc(tokenId);

    if (chargeDai > _fullHarvestThreshold) {
      return Status.FullDai;
    } else if (chargeUni > _fullHarvestThreshold) {
      return Status.FullUni;
    } else if (chargeUsdc > _fullHarvestThreshold) {
      return Status.FullUsdc;
    } else if (chargeDai > _halfHarvestThreshold) {
      return Status.HalfDai;
    } else if (chargeUni > _halfHarvestThreshold) {
      return Status.HalfUni;
    } else if (chargeUsdc > _halfHarvestThreshold) {
      return Status.HalfUsdc;
    }
    
    return Status.Planted;
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
    onlyTokenOwnerOrApproved(tokenId)
  {
    return _plantCrops(
      tokenId,
      walletManagerId,
      assetToken,
      assetAmount
    );
  }

  function harvest(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken
  )
    external
    virtual
    override
    nonReentrant
    whenNotPaused
    onlyTokenOwnerOrApproved(tokenId)
    returns (uint256 creatorAmount, uint256 receiverAmount) 
  {
    return _harvest(tokenId, walletManagerId, assetToken);
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

  /// @dev Setup the Asset Token Map
  function setAssetTokenMap(address daiToken, address uniToken, address usdcToken) external virtual onlyOwner {
    _assetSymbolToAssetToken["dai"] = daiToken;
    _assetSymbolToAssetToken["uni"] = uniToken;
    _assetSymbolToAssetToken["usdc"] = usdcToken;
  }

  /// @dev Setup the Status to tokenURI Map
  function setStatusToTokenURIMap(
    string memory emptyUri, 
    string memory plantedUri, 
    string memory halfDaiUri, 
    string memory halfUniUri, 
    string memory halfUsdcUri, 
    string memory fullDaiUri, 
    string memory fullUniUri, 
    string memory fullUsdcUri
  ) 
    external 
    virtual 
    onlyOwner 
  {
    _statusToTokenURI[Status.Empty] = emptyUri;
    _statusToTokenURI[Status.Planted] = plantedUri;
    _statusToTokenURI[Status.HalfDai] = halfDaiUri;
    _statusToTokenURI[Status.HalfUni] = halfUniUri;
    _statusToTokenURI[Status.HalfUsdc] = halfUsdcUri;
    _statusToTokenURI[Status.FullDai] = fullDaiUri;
    _statusToTokenURI[Status.FullUni] = fullUniUri;
    _statusToTokenURI[Status.FullUsdc] = fullUsdcUri;
  }

  function setHarvestThresholds(uint256 fullThreshold, uint256 halfThreshold) 
    external 
    virtual
    onlyOwner
  {
    _fullHarvestThreshold = fullThreshold;
    _halfHarvestThreshold = halfThreshold;
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

  function _getBaseParticleMass(
    address contractAddress,
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken
  ) 
    internal 
    virtual
    returns (uint256)
  {
    if (address(_chargedParticles) == address(0x0))
      return 0;

    return _chargedParticles.baseParticleMass(contractAddress, tokenId, walletManagerId, assetToken);
  }
  
  function _getCurrentParticleCharge(
    address contractAddress,
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken
  ) 
    internal 
    virtual
    returns (uint256)
  {
    if (address(_chargedParticles) == address(0x0))
      return 0;

    return _chargedParticles.currentParticleCharge(contractAddress, tokenId, walletManagerId, assetToken);
  }

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
    _tokenIdToTokenAddress[newTokenId] = address(this);

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
      address(0x0)  // blackhole (arg not used)
    );
  }

  function _harvest(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken
  )
    internal
    virtual
    returns (uint256 creatorAmount, uint256 receiverAmount)
  {
    require(address(_chargedParticles) != address(0x0), "PRT:E-107");

    _dischargeParticle(tokenId, walletManagerId, assetToken);
  }

  function _dischargeParticle(
    uint256 tokenId,
    string memory walletManagerId,
    address assetToken
  )
    internal
    virtual
    returns (uint256 creatorAmount, uint256 receiverAmount)
  {
    return _chargedParticles.dischargeParticle(
      _msgSender(),
      address(this),
      tokenId,
      walletManagerId,
      assetToken
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