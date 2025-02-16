//SPDX-License-Provider:MIT
pragma solidity ^0.8.19;

import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FlashLoanArbitrage is IFlashLoanReceiver, Ownable {
    IPool public aaveLendingPool;
    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Router02 public sushiSwapRouter;
    address public weth;

    constructor(
        address _aaveLendingPool,
        address _uniswapRouter,
        address _sushiswapRouter,
        address _weth
    ) Ownable(msg.sender) {
        aaveLendingPool = IPool(_aaveLendingPool);
        uniswapRouter = IUniswapV2Router(_uniswapRouter);
        sushiSwapRouter = IUniswapV2Router(_sushiswapRouter);
        weth = _weth;
    }

    function requestFlashLoan(
        address token,
        uint256 amount
    ) external onlyOwner {
        address receiver = address(this);
        address[] memory assets = new address[](1);
        assets[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; //no collateral required

        aaveLendingPool.flashLoan(
            receiver,
            assets,
            amounts,
            modes,
            receiver,
            "",
            0
        );
    }
    function executeOperation(
        address[] calldata assets,
        address[] calldata amounts,
        address[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(
            msg.sender == address(aaveLendingPool),
            "only aave can call this"
        );

        address token = assets[0];
        uint256 amount = amounts[0];
        uint256 fee = premiums[0];
        uint256 totalDebt = amount + fee;

        uint256 acquiredAmount = swapOnUniswap(token, amount);
        uint256 finalAmount = swapOnSushiswap(token, acquiredAmount);

        require(finalAmount > totalDebt, "Arbitrage not profitable");

        IERC20(token).approve(address(aaveLendingPool), totalDebt);
        IERC20(token).transfer(owner(), finalAmount - totalDebt);

        return true;
    }
}
