// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ImdWindowShopper} from "../src/ImdWindowShopper.sol";

/// @dev Deploys the token and performs the whole launch distribution in one call, as the factory does
/// in one transaction, so nothing depends on state surviving between top-level test calls.
contract OneCallLauncher {
    ImdWindowShopper public token;

    function launch(bytes32 salt, address distributor, address pool, address remainder, uint256 poolBps)
        external
        returns (ImdWindowShopper launched)
    {
        launched = new ImdWindowShopper{salt: salt}();
        token = launched;
        uint256 supply = launched.totalSupply();
        uint256 swarm = supply / 10;
        uint256 seeded = supply * poolBps / 10_000;
        require(launched.transfer(distributor, swarm), "swarm transfer failed");
        require(launched.transfer(pool, seeded), "seed transfer failed");
        require(launched.transfer(remainder, launched.balanceOf(address(this))), "remainder transfer failed");
    }
}

/// @notice Edge inputs and hostile callers the main suite does not reach.
contract ImdWindowShopperAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    ImdWindowShopper internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        token = new ImdWindowShopper();
    }

    function test_supplyIsExactlyTenToTheTwentySeventh() public view {
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.INITIAL_SUPPLY(), token.totalSupply());
    }

    function test_twoDeploymentsAreIndependent() public {
        ImdWindowShopper other = new ImdWindowShopper();
        token.transfer(alice, 1 ether);
        assertEq(other.balanceOf(alice), 0);
        assertEq(other.totalSupply(), SUPPLY);
        assertEq(other.balanceOf(address(this)), SUPPLY);
    }

    function test_create2SameSaltTwiceFails() public {
        OneCallLauncher launcher = new OneCallLauncher();
        launcher.launch(bytes32(uint256(7)), alice, bob, spender, 8_000);
        vm.expectRevert();
        launcher.launch(bytes32(uint256(7)), alice, bob, spender, 8_000);
    }

    function testFuzz_oneCallLaunchDistributesExactly(bytes32 salt, uint256 poolBps) public {
        poolBps = bound(poolBps, 0, 9_000);
        OneCallLauncher launcher = new OneCallLauncher();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address remainder = makeAddr("remainder");
        ImdWindowShopper launched = launcher.launch(salt, distributor, pool, remainder, poolBps);
        uint256 seeded = SUPPLY * poolBps / 10_000;
        assertEq(launched.balanceOf(address(launcher)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), seeded);
        assertEq(launched.balanceOf(remainder), SUPPLY - SUPPLY / 10 - seeded);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroAddressCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
    }

    function test_approveFromZeroAddressCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(alice, 1);
    }

    function test_transferFromZeroOwnerWithAmountReverts() public {
        // A non-zero amount fails the allowance check before the owner is validated.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 1);
    }

    function test_zeroAddressCannotBeGivenAnAllowanceToSpend() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_ownerApprovingThemselfStillNeedsAllowanceForTransferFrom() public {
        token.approve(address(this), 5);
        assertTrue(token.transferFrom(address(this), alice, 5));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 5);
    }

    function test_sameTransferTwiceExhaustsBalance() public {
        token.transfer(alice, 10);
        vm.startPrank(alice);
        assertTrue(token.transfer(bob, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        token.transfer(bob, 10);
        vm.stopPrank();
        assertEq(token.balanceOf(bob), 10);
    }

    function test_sameTransferFromTwiceExhaustsAllowance() public {
        token.approve(spender, 10);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), bob, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 10));
        token.transferFrom(address(this), bob, 10);
        vm.stopPrank();
        assertEq(token.balanceOf(bob), 10);
    }

    function test_allowanceAboveSupplyIsBoundedByBalance() public {
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        token.approve(spender, SUPPLY * 2);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 1 ether + 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether + 1);
        assertEq(token.allowance(alice, spender), SUPPLY * 2);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function test_maxMinusOneAllowanceIsFiniteAndDecreases() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    function test_nonPayableEntrypointsRejectEther() public {
        vm.deal(address(this), 3 ether);
        (bool ok,) = address(token).call{value: 1 ether}(abi.encodeCall(token.transfer, (alice, 1)));
        assertFalse(ok);
        (ok,) = address(token).call{value: 1 ether}(abi.encodeCall(token.approve, (alice, 1)));
        assertFalse(ok);
        (ok,) = address(token).call{value: 1 ether}(abi.encodeCall(token.transferFrom, (address(this), alice, 0)));
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), alice), 0);
    }

    function test_truncatedCalldataReverts() public {
        bytes memory full = abi.encodeCall(token.transfer, (alice, 1 ether));
        bytes memory truncated = new bytes(full.length - 1);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = full[i];
        }
        (bool ok,) = address(token).call(truncated);
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        (ok,) = address(token).call(hex"00");
        assertFalse(ok);
    }

    function testFuzz_unknownSelectorsNeverSucceed(bytes4 selector, bytes calldata tail) public {
        vm.assume(
            selector != token.transfer.selector && selector != token.approve.selector
                && selector != token.transferFrom.selector && selector != token.balanceOf.selector
                && selector != token.allowance.selector && selector != token.totalSupply.selector
                && selector != token.name.selector && selector != token.symbol.selector
                && selector != token.decimals.selector && selector != token.INITIAL_SUPPLY.selector
        );
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodePacked(selector, tail));
        assertFalse(ok);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_approveStoresExactValue(address owner, address who, uint256 amount) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        who = address(uint160(bound(uint160(who), 1, type(uint160).max)));
        vm.prank(owner);
        assertTrue(token.approve(who, amount));
        assertEq(token.allowance(owner, who), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferToAnyNonZeroRecipient(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        uint256 before = token.balanceOf(recipient);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(recipient), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), before + amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_infiniteAllowanceNeverDecreases(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, first);
        token.transferFrom(address(this), bob, second);
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - first - second);
    }

    function testFuzz_strangerCannotMoveHolderFunds(address stranger, uint256 amount) public {
        vm.assume(stranger != address(0) && stranger != alice);
        amount = bound(amount, 1, 1 ether);
        token.transfer(alice, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(alice, stranger, amount);
        assertEq(token.balanceOf(alice), 1 ether);
    }
}

/// @dev Drives successful and deliberately failing calls in random order. Failing calls must revert
/// with the exact ERC-20 error and leave balances and allowances untouched.
contract HostileHandler is Test {
    ImdWindowShopper public immutable token;
    address[5] public actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    uint256 public ghostMoved;
    uint256 public failuresChecked;

    constructor(ImdWindowShopper token_, address factory) {
        token = token_;
        actors[0] = factory;
        for (uint256 i = 1; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("hostile actor ", vm.toString(i)));
        }
        ghostBalance[factory] = token_.totalSupply();
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMoved += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostMoved += amount;
    }

    function overspendBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = ghostBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.prank(from);
        try token.transfer(to, amount) {
            revert("transfer above balance succeeded");
        } catch (bytes memory reason) {
            assertEq(
                reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
        failuresChecked++;
    }

    function overspendAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            revert("transferFrom above allowance succeeded");
        } catch (bytes memory reason) {
            assertEq(
                reason,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        }
        failuresChecked++;
    }

    function sendToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            revert("transfer to zero succeeded");
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        }
        failuresChecked++;
    }

    function callAdminSelector(uint256 callerSeed, uint8 which, uint256 amount) external {
        address caller = _actor(callerSeed);
        bytes[6] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", caller, amount),
            abi.encodeWithSignature("burn(uint256)", amount),
            abi.encodeWithSignature("burnFrom(address,uint256)", actors[1], amount),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", actors[1]),
            abi.encodeWithSignature("transferOwnership(address)", caller)
        ];
        vm.prank(caller);
        (bool ok,) = address(token).call(calls[which % calls.length]);
        assertFalse(ok, "administrative entrypoint exists");
        failuresChecked++;
    }

    function sumOfBalances() external view returns (uint256 sum) {
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
    }
}

contract ImdWindowShopperHostileInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    ImdWindowShopper internal token;
    HostileHandler internal handler;
    OneCallLauncher internal launcher;

    function setUp() public {
        // The supply starts in a factory-like contract, as it does at launch, and moves from there.
        launcher = new OneCallLauncher();
        vm.prank(address(launcher));
        token = new ImdWindowShopper();
        handler = new HostileHandler(token, address(launcher));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = HostileHandler.transfer.selector;
        selectors[1] = HostileHandler.approve.selector;
        selectors[2] = HostileHandler.transferFrom.selector;
        selectors[3] = HostileHandler.overspendBalance.selector;
        selectors[4] = HostileHandler.overspendAllowance.selector;
        selectors[5] = HostileHandler.sendToZero.selector;
        selectors[6] = HostileHandler.callAdminSelector.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_supplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(handler.sumOfBalances(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesAndAllowancesMatchGhosts() public view {
        for (uint256 i; i < 5; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.ghostBalance(owner));
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender));
            }
        }
    }
}
