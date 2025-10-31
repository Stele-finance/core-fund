// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

// Direct Uniswap V3 interfaces
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) 
        external view returns (address pool);
}

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

/// @title Price Oracle Library
/// @notice Library for calculating Spot Prices using Uniswap V3
/// @dev Provides functions for spot price calculation, tick math, and price conversion
library PriceOracle {

    // Standard Uniswap V3 fee tiers - using function to return array
    function getFeeTiers() private pure returns (uint16[3] memory) {
        return [uint16(500), uint16(3000), uint16(10000)]; // 0.05%, 0.3%, 1%
    }

    /// @notice Convert tick to sqrt price ratio
    /// @param tick The tick value
    /// @return sqrtPriceX96 The sqrt price in X96 format
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(int256(887272)), 'T');

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /// @notice Full precision multiplication
    /// @param a First number
    /// @param b Second number  
    /// @param denominator Denominator for division
    /// @return result The result of (a * b) / denominator
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        require(denominator > prod1);

        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos = (~denominator + 1) & denominator;
        assembly {
            denominator := div(denominator, twos)
        }

        assembly {
            prod0 := div(prod0, twos)
        }
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        uint256 inv = (3 * denominator) ^ 2;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;

        result = prod0 * inv;
        return result;
    }

    /// @notice Convert tick to price quote
    /// @param tick The tick value
    /// @param baseAmount The base amount to convert
    /// @param baseToken The base token address
    /// @param quoteToken The quote token address
    /// @return quoteAmount The calculated quote amount
    function getQuoteAtTick(
        int24 tick, 
        uint128 baseAmount, 
        address baseToken, 
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = getSqrtRatioAtTick(tick);
        
        // Calculate the price ratio from sqrtRatioX96
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? mulDiv(ratioX192, baseAmount, 1 << 192)
                : mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? mulDiv(ratioX128, baseAmount, 1 << 128)
                : mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /// @notice Get quote from pool using spot price
    /// @param pool The pool address
    /// @param baseAmount The base amount
    /// @param baseToken The base token address
    /// @param quoteToken The quote token address
    /// @return quoteAmount The calculated quote amount
    function getQuoteFromPool(
        address pool,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal view returns (uint256 quoteAmount) {
        // Use spot price (like Uniswap SwapRouter)
        (, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();

        return getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);
    }

    /// @notice Get best quote across multiple fee tiers using spot price
    /// @param factory The Uniswap V3 factory address
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param amountIn Input amount
    /// @return bestQuote The best quote found across all pools
    function getBestQuote(
        address factory,
        address tokenA,
        address tokenB,
        uint128 amountIn
    ) internal view returns (uint256 bestQuote) {
        bestQuote = 0;
        
        uint16[3] memory feeTiers = getFeeTiers();
        for (uint256 i = 0; i < feeTiers.length; i++) {
            address pool = IUniswapV3Factory(factory).getPool(tokenA, tokenB, uint24(feeTiers[i]));
            if (pool == address(0)) {
                continue;
            }

            // Note: Direct call without try-catch since we're in a library
            // The calling contract should handle exceptions
            uint256 quote = getQuoteFromPool(pool, amountIn, tokenA, tokenB);
            if (quote > bestQuote) {
                bestQuote = quote;
            }
        }
    }

    /// @notice Get ETH price in USD using spot price
    /// @dev Reverts if no valid price is available
    /// @param factory The Uniswap V3 factory address
    /// @param weth9 WETH9 token address
    /// @param usdToken USD token address (e.g., USDC)
    /// @return ethPriceUSD ETH price in USD
    function getETHPriceUSD(
        address factory,
        address weth9,
        address usdToken
    ) internal view returns (uint256 ethPriceUSD) {
        uint256 quote = getBestQuote(
            factory,
            weth9,
            usdToken,
            uint128(1e18) // 1 ETH
        );

        require(quote > 0, "No valid ETH price available");
        return quote;
    }

    /// @notice Get token price in ETH using spot price
    /// @param factory The Uniswap V3 factory address
    /// @param token Token address
    /// @param weth9 WETH9 token address
    /// @param amount Token amount
    /// @return ethAmount ETH amount equivalent
    function getTokenPriceETH(
        address factory,
        address token,
        address weth9,
        uint256 amount
    ) internal view returns (uint256 ethAmount) {
        if (token == weth9) {
            return amount; // 1:1 ratio for WETH to ETH
        }

        return getBestQuote(
            factory,
            token,
            weth9,
            uint128(amount)
        );
    }

    /// @notice Get token price in USD using spot price
    /// @param factory The Uniswap V3 factory address
    /// @param token Token address
    /// @param amount Token amount
    /// @param weth9 WETH9 token address
    /// @param usdToken USD token address (e.g., USDC)
    /// @return usdAmount USD amount equivalent
    function getTokenPriceUSD(
        address factory,
        address token,
        uint256 amount,
        address weth9,
        address usdToken
    ) internal view returns (uint256 usdAmount) {
        if (token == weth9) {
            // ETH to USD directly
            uint256 ethPriceUSD = getETHPriceUSD(factory, weth9, usdToken);
            return precisionMul(amount, ethPriceUSD, 1e18);
        } else if (token == usdToken) {
            // USD token (USDC) - return as is
            return amount;
        } else {
            // Other tokens: token -> ETH -> USD
            uint256 ethAmount = getTokenPriceETH(factory, token, weth9, amount);
            if (ethAmount == 0) return 0;

            uint256 ethPriceUSD = getETHPriceUSD(factory, weth9, usdToken);
            return precisionMul(ethAmount, ethPriceUSD, 1e18);
        }
    }
    
    /// @notice High precision multiplication: (a * b) / c
    /// @param a First number
    /// @param b Second number
    /// @param c Divisor
    /// @return result The result of (a * b) / c with high precision
    function precisionMul(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(c > 0, "Division by zero");
        
        uint256 PRECISION_SCALE = 1e18;
        
        // Check if we can safely multiply with precision scale
        if (a <= type(uint256).max / b && (a * b) <= type(uint256).max / PRECISION_SCALE) {
            return (a * b * PRECISION_SCALE) / (c * PRECISION_SCALE);
        }
        
        // Fallback to standard calculation to avoid overflow
        return (a * b) / c;
    }
}