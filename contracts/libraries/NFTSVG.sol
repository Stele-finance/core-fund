// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

library NFTSVG {
    using Strings for uint256;
    using Strings for address;

    struct SVGParams {
        uint256 fundId;
        address manager;
        uint256 fundCreatedTime;   // Fund creation timestamp
        uint256 nftMintTime;       // NFT mint timestamp
        uint256 investment;        // Investment amount
        uint256 currentValue;      // Current investment value
        int256 returnRate;         // Return rate
    }

    function generateSVG(SVGParams memory params) internal pure returns (string memory) {
        string memory returnColor = params.returnRate >= 0 ? "#10B981" : "#EF4444";
        string memory returnSign = params.returnRate >= 0 ? "+" : "";
        
        return string(abi.encodePacked(
            '<svg width="500" height="700" viewBox="0 0 500 700" xmlns="http://www.w3.org/2000/svg">',
            '<defs>',
                '<filter id="glow">',
                    '<feGaussianBlur stdDeviation="2" result="coloredBlur"/>',
                    '<feMerge>',
                        '<feMergeNode in="coloredBlur"/>',
                        '<feMergeNode in="SourceGraphic"/>',
                    '</feMerge>',
                '</filter>',
            '</defs>',
            generateBackground(),
            generateHeader(params.fundId),
            generateDataRows(params, returnColor, returnSign),
            generateFooter(params.manager),
            '</svg>'
        ));
    }

    function generateBackground() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect width="500" height="700" fill="#1F1F23" rx="24" ry="24"/>',
            '<rect x="20" y="20" width="460" height="660" fill="#2A2A2E" rx="20" ry="20" stroke="#404040" stroke-width="1"/>'
        ));
    }

    function generateHeader(uint256 fundId) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="250" y="70" font-family="SF Pro Display, -apple-system, sans-serif" font-size="24" font-weight="600" fill="#FFFFFF" text-anchor="middle">',
            'Stele Fund Manager',
            '</text>',
            '<text x="250" y="100" font-family="SF Pro Display, -apple-system, sans-serif" font-size="16" fill="#9CA3AF" text-anchor="middle">',
            'Certificate #', fundId.toString(),
            '</text>'
        ));
    }

    function generateDataRows(SVGParams memory params, string memory returnColor, string memory returnSign) internal pure returns (string memory) {
        uint256 absRate = params.returnRate >= 0 ? uint256(params.returnRate) : uint256(-params.returnRate);
        string memory profitStr = string(abi.encodePacked(
            returnSign,
            (absRate / 100).toString(),
            '.',
            formatDecimals(absRate % 100),
            '%'
        ));
        
        return string(abi.encodePacked(
            generateDataRow('Fund ID', string(abi.encodePacked('#', params.fundId.toString())), '#FFFFFF', 140),
            generateDataRow('Investment', formatAmount(params.investment), '#FFFFFF', 190),
            generateDataRow('Current Value', formatAmount(params.currentValue), '#FFFFFF', 240),
            generateDataRow('Profit', profitStr, returnColor, 290),
            generateDataRow('Fund Created', timestampToDateString(params.fundCreatedTime), '#9CA3AF', 340),
            generateDataRow('NFT Minted', timestampToDateString(params.nftMintTime), '#9CA3AF', 390)
        ));
    }

    function generateDataRow(string memory label, string memory value, string memory valueColor, uint256 yPos) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="60" y="', (yPos + 20).toString(), '" font-family="SF Pro Display, -apple-system, sans-serif" font-size="16" font-weight="400" fill="#9CA3AF">',
            label,
            '</text>',
            '<text x="440" y="', (yPos + 20).toString(), '" font-family="SF Pro Display, -apple-system, sans-serif" font-size="16" font-weight="600" fill="', valueColor, '" text-anchor="end">',
            value,
            '</text>',
            yPos < 390 ? string(abi.encodePacked('<line x1="60" y1="', (yPos + 30).toString(), '" x2="440" y2="', (yPos + 30).toString(), '" stroke="#404040" stroke-width="1"/>')) : ''
        ));
    }


    function generateFooter(address manager) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<line x1="60" y1="430" x2="440" y2="430" stroke="#404040" stroke-width="1"/>',
            '<text x="250" y="470" font-family="SF Pro Display, -apple-system, sans-serif" font-size="12" fill="#6B7280" text-anchor="middle">',
            'Manager: ', addressToString(manager),
            '</text>',
            '<text x="250" y="500" font-family="SF Pro Display, -apple-system, sans-serif" font-size="14" font-weight="600" fill="#FFFFFF" text-anchor="middle">',
            'SteleFund Protocol',
            '</text>',
            '<circle cx="250" cy="530" r="6" fill="', getManagerColor(manager), '"/>',
            '<circle cx="250" cy="530" r="3" fill="#FFFFFF"/>'
        ));
    }

    function formatAmount(uint256 amount) internal pure returns (string memory) {
        if (amount >= 1e24) { // >= 1M tokens (18 decimals)
            return string(abi.encodePacked(
                '$', (amount / 1e24).toString(), '.', formatDecimals((amount % 1e24) / 1e22), 'M'
            ));
        } else if (amount >= 1e21) { // >= 1K tokens
            return string(abi.encodePacked(
                '$', (amount / 1e21).toString(), '.', formatDecimals((amount % 1e21) / 1e19), 'K'
            ));
        } else if (amount >= 1e18) {
            return string(abi.encodePacked('$', (amount / 1e18).toString()));
        } else if (amount == 0) {
            return '$0.00';
        } else {
            return string(abi.encodePacked('$', amount.toString()));
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


    // Convert timestamp to date string (YYYY-MM-DD)
    function timestampToDateString(uint256 timestamp) internal pure returns (string memory) {
        // Days since Unix epoch (January 1, 1970)
        uint256 daysSinceEpoch = timestamp / 86400; // 86400 seconds in a day
        
        // Calculate year (approximate)
        uint256 year = 1970 + (daysSinceEpoch / 365);
        
        // Adjust for leap years (rough approximation)
        uint256 leapYearAdjustment = (year - 1970) / 4;
        uint256 adjustedDays = daysSinceEpoch - leapYearAdjustment;
        year = 1970 + (adjustedDays / 365);
        
        // Calculate remaining days in the year
        uint256 yearStartDays = (year - 1970) * 365 + ((year - 1970) / 4);
        uint256 dayOfYear = daysSinceEpoch - yearStartDays;
        
        // Simple month calculation (approximate)
        uint256 month;
        uint256 day;
        
        if (dayOfYear <= 31) {
            month = 1; day = dayOfYear;
        } else if (dayOfYear <= 59) {
            month = 2; day = dayOfYear - 31;
        } else if (dayOfYear <= 90) {
            month = 3; day = dayOfYear - 59;
        } else if (dayOfYear <= 120) {
            month = 4; day = dayOfYear - 90;
        } else if (dayOfYear <= 151) {
            month = 5; day = dayOfYear - 120;
        } else if (dayOfYear <= 181) {
            month = 6; day = dayOfYear - 151;
        } else if (dayOfYear <= 212) {
            month = 7; day = dayOfYear - 181;
        } else if (dayOfYear <= 243) {
            month = 8; day = dayOfYear - 212;
        } else if (dayOfYear <= 273) {
            month = 9; day = dayOfYear - 243;
        } else if (dayOfYear <= 304) {
            month = 10; day = dayOfYear - 273;
        } else if (dayOfYear <= 334) {
            month = 11; day = dayOfYear - 304;
        } else {
            month = 12; day = dayOfYear - 334;
        }
        
        // Handle edge cases
        if (day == 0) day = 1;
        if (day > 31) day = 31;
        
        return string(abi.encodePacked(
            year.toString(),
            "-",
            month < 10 ? "0" : "", month.toString(),
            "-",
            day < 10 ? "0" : "", day.toString()
        ));
    }
}