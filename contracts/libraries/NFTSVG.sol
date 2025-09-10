// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

library NFTSVG {
    using Strings for uint256;
    using Strings for address;

    uint256 constant USDC_DECIMALS = 6;

    struct SVGParams {
        uint256 fundId;
        address manager;
        uint256 fundCreated;  // Fund creation block number
        uint256 nftMintBlock;      // NFT mint block number
        uint256 investment;        // Investment amount
        uint256 currentValue;      // Current investment value
        int256 returnRate;         // Return rate
    }

    function generateSVG(SVGParams memory params) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg width="300" height="400" viewBox="0 0 300 400" xmlns="http://www.w3.org/2000/svg">',
            generateDefs(),
            generateCard(),
            generateTitle(),
            generateRankBadge(params.fundId),
            generateStatsGrid(params),
            generateSeparator(),
            generateInvestmentSummary(params),
            generateFooter(),
            '</svg>'
        ));
    }

    function generateDefs() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<defs>',
                '<linearGradient id="orangeGradient" x1="0%" y1="0%" x2="100%" y2="100%">',
                    '<stop offset="0%" style="stop-color:#ff8c42;stop-opacity:1" />',
                    '<stop offset="100%" style="stop-color:#e55100;stop-opacity:1" />',
                '</linearGradient>',
                '<linearGradient id="cardBackground" x1="0%" y1="0%" x2="0%" y2="100%">',
                    '<stop offset="0%" style="stop-color:#2a2a2e;stop-opacity:1" />',
                    '<stop offset="100%" style="stop-color:#1f1f23;stop-opacity:1" />',
                '</linearGradient>',
                '<filter id="cardShadow">',
                    '<feDropShadow dx="0" dy="2" stdDeviation="8" flood-color="#000" flood-opacity="0.06"/>',
                '</filter>',
            '</defs>'
        ));
    }

    function generateCard() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect width="300" height="400" rx="12" fill="url(#cardBackground)" stroke="#404040" stroke-width="1" filter="url(#cardShadow)"/>',
            '<rect x="0" y="0" width="300" height="4" rx="12" fill="url(#orangeGradient)"/>'
        ));
    }

    function generateTitle() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="24" y="40" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="20" font-weight="600" fill="#f9fafb">',
                'Fund Performance',
            '</text>',
            '<text x="24" y="60" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="14" fill="#9ca3af">',
                'Stele Protocol',
            '</text>'
        ));
    }

    function generateRankBadge(uint256 fundId) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="24" y="85" width="80" height="32" rx="16" fill="url(#orangeGradient)"/>',
            '<text x="64" y="103" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="14" font-weight="600" fill="#ffffff" text-anchor="middle">',
                'Fund #', fundId.toString(),
            '</text>'
        ));
    }

    function generateStatsGrid(SVGParams memory params) internal pure returns (string memory) {
        string memory returnText = formatReturnRate(params.returnRate);
        string memory returnColor = params.returnRate >= 0 ? "#10b981" : "#ef4444";
        
        return string(abi.encodePacked(
            '<g font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">',
                '<text x="24" y="140" font-size="14" font-weight="500" fill="#9ca3af">Fund ID</text>',
                '<text x="276" y="140" font-size="14" font-weight="600" fill="#f9fafb" text-anchor="end">#', params.fundId.toString(), '</text>',
                '<text x="24" y="165" font-size="14" font-weight="500" fill="#9ca3af">Manager</text>',
                '<text x="276" y="165" font-size="14" font-weight="600" fill="#f9fafb" text-anchor="end">', addressToString(params.manager), '</text>',
                '<text x="24" y="190" font-size="14" font-weight="500" fill="#9ca3af">Created</text>',
                '<text x="276" y="190" font-size="14" font-weight="600" fill="#f9fafb" text-anchor="end">', params.fundCreated.toString(), '</text>',
                '<text x="24" y="215" font-size="14" font-weight="500" fill="#9ca3af">Minted</text>',
                '<text x="276" y="215" font-size="14" font-weight="600" fill="#f9fafb" text-anchor="end">', params.nftMintBlock.toString(), '</text>',
                '<text x="24" y="240" font-size="14" font-weight="500" fill="#9ca3af">Return Rate</text>',
                '<text x="276" y="240" font-size="16" font-weight="700" fill="', returnColor, '" text-anchor="end">', returnText, '</text>',
            '</g>'
        ));
    }

    function generateSeparator() internal pure returns (string memory) {
        return '<line x1="24" y1="270" x2="276" y2="270" stroke="#404040" stroke-width="1"/>';
    }

    function generateInvestmentSummary(SVGParams memory params) internal pure returns (string memory) {
        uint256 profit = params.returnRate >= 0 ? 
            params.currentValue - params.investment : 
            params.investment - params.currentValue;
        string memory profitSign = params.returnRate >= 0 ? "+" : "-";
        string memory profitColor = params.returnRate >= 0 ? "#10b981" : "#ef4444";
        
        return string(abi.encodePacked(
            '<g font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">',
                '<text x="24" y="295" font-size="14" font-weight="500" fill="#9ca3af">Investment</text>',
                '<text x="276" y="295" font-size="14" font-weight="600" fill="#f9fafb" text-anchor="end">', formatAmount(params.investment), '</text>',
                '<text x="24" y="320" font-size="14" font-weight="500" fill="#9ca3af">Current Value</text>',
                '<text x="276" y="320" font-size="14" font-weight="600" fill="#f9fafb" text-anchor="end">', formatAmount(params.currentValue), '</text>',
                '<text x="24" y="345" font-size="14" font-weight="500" fill="#9ca3af">Profit</text>',
                '<text x="276" y="345" font-size="14" font-weight="600" fill="', profitColor, '" text-anchor="end">', profitSign, formatAmount(profit), '</text>',
            '</g>'
        ));
    }

    function formatReturnRate(int256 returnRate) internal pure returns (string memory) {
        if (returnRate >= 0) {
            uint256 absRate = uint256(returnRate);
            return string(abi.encodePacked(
                "+", 
                (absRate / 100).toString(), 
                ".", 
                formatDecimals(absRate % 100), 
                "%"
            ));
        } else {
            uint256 absRate = uint256(-returnRate);
            return string(abi.encodePacked(
                "-", 
                (absRate / 100).toString(), 
                ".", 
                formatDecimals(absRate % 100), 
                "%"
            ));
        }
    }


    function generateFooter() internal pure returns (string memory) {
        return '<text x="150" y="380" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="12" font-weight="500" fill="#9ca3af" text-anchor="middle">Powered by Stele Protocol</text>';
    }

    function formatAmount(uint256 amount) internal pure returns (string memory) {
        uint256 oneToken = 10 ** USDC_DECIMALS;
        uint256 millionTokens = oneToken * 1e6;
        uint256 thousandTokens = oneToken * 1e3;
        
        if (amount >= millionTokens) { // >= 1M USDC
            uint256 whole = amount / millionTokens;
            uint256 fraction = (amount % millionTokens) / (millionTokens / 100); // 2 decimal places
            return string(abi.encodePacked(
                '$', whole.toString(), '.', formatDecimals(fraction), 'M'
            ));
        } else if (amount >= thousandTokens) { // >= 1K USDC
            uint256 whole = amount / thousandTokens;
            uint256 fraction = (amount % thousandTokens) / (thousandTokens / 100); // 2 decimal places
            return string(abi.encodePacked(
                '$', whole.toString(), '.', formatDecimals(fraction), 'K'
            ));
        } else if (amount >= oneToken) { // >= 1 USDC
            uint256 whole = amount / oneToken;
            uint256 fraction = (amount % oneToken) / (oneToken / 100); // 2 decimal places
            return string(abi.encodePacked('$', whole.toString(), '.', formatDecimals(fraction)));
        } else if (amount == 0) {
            return '$0.00';
        } else {
            // Less than 1 USDC
            uint256 fraction = (amount * 100) / oneToken; // 2 decimal places
            return string(abi.encodePacked('$0.', formatDecimals(fraction)));
        }
    }

    function formatDecimals(uint256 value) internal pure returns (string memory) {
        if (value < 10) {
            return string(abi.encodePacked('0', value.toString()));
        }
        return value.toString();
    }

    function addressToString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(10);
        
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 4; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        
        return string(abi.encodePacked(string(str), '...'));
    }

    function getManagerColor(address manager) internal pure returns (string memory) {
        bytes32 hash = keccak256(abi.encodePacked(manager));
        uint256 hue = uint256(hash) % 360;
        return string(abi.encodePacked('hsl(', hue.toString(), ', 70%, 50%)'));
    }

}