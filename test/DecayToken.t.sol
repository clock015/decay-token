// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DecayToken.sol";

contract DecayTokenTest is Test {
    DecayToken public token;

    address owner = address(1);
    address alice = address(2);
    address bob = address(3);

    uint256 constant INITIAL_SUPPLY = 1_000_000; // 100万
    uint256 constant HALF_LIFE = 1 days; // 半衰期设为1天

    function setUp() public {
        vm.startPrank(owner);
        // 【关键改动】：增加了 "HalfLifeToken" 和 "HLT" 两个参数
        token = new DecayToken(
            "HalfLife Token",
            "HLT",
            INITIAL_SUPPLY,
            HALF_LIFE
        );
        vm.stopPrank();
    }

    // 1. 测试初始状态
    function testInitialState() public {
        assertEq(token.totalSupply(), INITIAL_SUPPLY * 1e18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY * 1e18);
        assertEq(token.name(), "HalfLife Token");
        assertEq(token.symbol(), "HLT");
    }

    // 2. 测试经过一个半衰期后的衰减
    function testDecayAfterOneHalfLife() public {
        skip(HALF_LIFE);
        uint256 expected = (INITIAL_SUPPLY * 1e18) / 2;
        // 允许 1 wei 的舍入误差
        assertApproxEqAbs(token.balanceOf(owner), expected, 1);
        assertApproxEqAbs(token.totalSupply(), expected, 1);
    }

    // 3. 测试转账时的自动结算逻辑
    function testTransferSettlement() public {
        uint256 transferAmount = 100 ether;

        // 快进半天
        skip(HALF_LIFE / 2);
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        token.transfer(alice, transferAmount);

        // 检查接收方是否足额收到
        assertEq(token.balanceOf(alice), transferAmount);
        // 检查发送方是否扣除正确（基于衰减后的值）
        assertApproxEqAbs(
            token.balanceOf(owner),
            ownerBalanceBefore - transferAmount,
            1
        );
    }

    // 4. 测试持币比例一致性 (核心逻辑)
    function testShareConsistency() public {
        // 分配 20% 给 Alice
        vm.prank(owner);
        token.transfer(alice, 200_000 ether);

        uint256 initialTotal = token.totalSupply();
        uint256 initialAlice = token.balanceOf(alice);
        uint256 initialRatio = (initialAlice * 1e18) / initialTotal;

        // 快进一个随机的时间：15.5 天
        skip(15 days + 12 hours);

        uint256 totalAfter = token.totalSupply();
        uint256 aliceAfter = token.balanceOf(alice);
        uint256 ratioAfter = (aliceAfter * 1e18) / totalAfter;

        // 尽管余额变小了，但 Alice 占总量的比例应该几乎不变
        assertApproxEqAbs(ratioAfter, initialRatio, 1e10);
        assertTrue(aliceAfter < initialAlice);
    }

    // 5. 测试授权与 transferFrom
    function testTransferFromWithDecay() public {
        uint256 allowanceAmount = 5000 ether;
        vm.prank(owner);
        token.approve(alice, allowanceAmount);

        skip(2 days); // 衰减两天

        uint256 spendAmount = 1000 ether;
        vm.prank(alice);
        token.transferFrom(owner, bob, spendAmount);

        assertEq(token.balanceOf(bob), spendAmount);
        assertEq(token.allowance(owner, alice), allowanceAmount - spendAmount);
    }

    // 6. 测试极限衰减（归零）
    function testExtremeDecay() public {
        // 135个半衰期后，余额应该由于安全阈值判断变为 0
        skip(HALF_LIFE * 135);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.totalSupply(), 0);
    }

    // 7. 测试铸造 (Mint)
    function testMint() public {
        uint256 mintAmount = 500_000 ether;
        skip(1 days); // 先衰减一天 (总量剩 50万)

        uint256 supplyBefore = token.totalSupply();

        token.mint(bob, mintAmount); // 铸造 50万

        // 总量应该接近 100万 (50万残余 + 50万新铸造)
        assertApproxEqAbs(token.totalSupply(), supplyBefore + mintAmount, 1);
        assertEq(token.balanceOf(bob), mintAmount);
    }
}
