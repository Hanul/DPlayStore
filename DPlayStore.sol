pragma solidity ^0.5.9;

import "./DPlayStoreInterface.sol";
import "./DPlayCoinInterface.sol";
import "./Util/NetworkChecker.sol";
import "./Util/SafeMath.sol";

contract DPlayStore is DPlayStoreInterface, NetworkChecker {
	using SafeMath for uint;
	
	uint8 constant private RATING_DECIMALS = 18;
	
	Game[] private games;
	
	mapping(address => uint[]) private publisherToGameIds;
	mapping(uint => mapping(string => GameDetails)) private gameIdToLanguageToDetails;
	
	mapping(address => uint[]) private buyerToGameIds;
	mapping(uint => address[]) private gameIdToBuyers;
	
	mapping(uint => Rating[]) private gameIdToRatings;
	
	DPlayCoinInterface private dplayCoin;
	
	constructor() NetworkChecker() public {
		
		// DPlay Coin 스마트 계약을 불러옵니다.
		if (network == Network.Mainnet) {
			//TODO
		} else if (network == Network.Kovan) {
			dplayCoin = DPlayCoinInterface(0x8079bA69E89237a4B739fF57337109fDAbD8CCa0);
		} else if (network == Network.Ropsten) {
			//TODO
		} else if (network == Network.Rinkeby) {
			//TODO
		} else {
			revert();
		}
	}
	
	function ratingDecimals() external view returns (uint8) {
		return RATING_DECIMALS;
	}
	
	// 게임의 개수를 반환합니다.
	function getGameCount() external view returns (uint) {
		return games.length;
	}
	
	// 새 게임을 생성합니다.
	function newGame(uint price, string calldata gameURL, bool isWebGame, string calldata defaultLanguage) external returns (uint) {
		
		// 게임의 가격은 무료이거나 1DC 이상이여야 합니다.
		require(price == 0 || price >= 10 ** uint(dplayCoin.decimals()));
		
		uint createTime = now;
		
		uint gameId = games.push(Game({
			publisher		: msg.sender,
			isPublished		: false,
			price			: price,
			gameURL			: gameURL,
			isWebGame		: isWebGame,
			defaultLanguage	: defaultLanguage,
			createTime		: createTime,
			lastUpdateTime	: createTime,
			publishTime		: 0
		})).sub(1);
		
		publisherToGameIds[msg.sender].push(gameId);
		
		return gameId;
	}
	
	// 특정 주소가 배포자인지 확인합니다.
	function checkIsPublisher(address addr, uint gameId) external view returns (bool) {
		return games[gameId].publisher == addr;
	}
	
	// 게임의 정보를 반환합니다.
	function getGameInfo(uint gameId) external view returns (
		address publisher,
		bool isPublished,
		uint price,
		string memory gameURL,
		bool isWebGame,
		string memory defaultLanguage,
		uint createTime,
		uint lastUpdateTime
	) {
		
		Game storage game = games[gameId];
		
		return (
			game.publisher,
			game.isPublished,
			game.price,
			game.gameURL,
			game.isWebGame,
			game.defaultLanguage,
			game.createTime,
			game.lastUpdateTime
		);
	}
	
	// 게임의 가격을 변경합니다.
	function changePrice(uint gameId, uint price) external {
		
		Game storage game = games[gameId];
		
		// 무료 게임은 가격을 변경할 수 없습니다.
		require(game.price > 0);
		
		// 게임의 배포자인 경우에만
		require(game.publisher == msg.sender);
		
		// 게임의 가격은 1DC 이상이여야 합니다.
		require(price >= 10 ** uint(dplayCoin.decimals()));
		
		game.price = price;
		
		emit ChangePrice(gameId, price);
	}
	
	// 게임의 정보를 변경합니다.
	function changeGameInfo(uint gameId, string calldata gameURL, bool isWebGame, string calldata defaultLanguage) external {
		
		Game storage game = games[gameId];
		
		// 게임의 배포자인 경우에만
		require(game.publisher == msg.sender);
		
		game.gameURL = gameURL;
		game.isWebGame = isWebGame;
		game.defaultLanguage = defaultLanguage;
		
		emit ChangeGameInfo(gameId, gameURL, isWebGame, defaultLanguage);
	}
	
	// 언어별로 게임의 세부 정보를 입력합니다.
	function setGameDetails(
		uint gameId,
		string calldata language,
		string calldata title,
		string calldata summary,
		string calldata description,
		string calldata titleImageURL,
		string calldata bannerImageURL) external {
		
		// 게임의 배포자인 경우에만
		require(games[gameId].publisher == msg.sender);
		
		gameIdToLanguageToDetails[gameId][language] = GameDetails({
			title : title,
			summary : summary,
			description : description,
			titleImageURL : titleImageURL,
			bannerImageURL : bannerImageURL
		});
		
		games[gameId].lastUpdateTime = now;
	}
	
	// 게임의 세부 정보를 반환합니다.
	function getGameDetails(uint gameId, string calldata language) external view returns (
		string memory title,
		string memory summary,
		string memory description,
		string memory titleImageURL,
		string memory bannerImageURL
	) {
		
		GameDetails memory gameDetails = gameIdToLanguageToDetails[gameId][language];
		
		return (
			gameDetails.title,
			gameDetails.summary,
			gameDetails.description,
			gameDetails.titleImageURL,
			gameDetails.bannerImageURL
		);
	}
	
	// 게임을 출시합니다.
	function publish(uint gameId) external {
		
		Game storage game = games[gameId];
		
		// 게임의 배포자인 경우에만
		require(game.publisher == msg.sender);
		
		game.isPublished = true;
		
		// 최초 출시인 경우에만 출시 시간 저장
		if (game.publishTime == 0) {
			game.publishTime = now;
		}
		
		emit Publish(gameId);
	}
	
	// 게임 출시를 취소합니다.
	function unpublish(uint gameId) external {
		
		Game storage game = games[gameId];
		
		// 게임의 배포자인 경우에만
		require(game.publisher == msg.sender);
		
		game.isPublished = false;
		
		emit Unpublish(gameId);
	}
	
	// 게임을 구매합니다.
	function buy(uint gameId) external payable {
		
		Game memory game = games[gameId];
		
		// 정상적인 게임 정보여야 합니다.
		require(game.publisher != address(0x0));
		
		// 무료 게임은 구매할 수 없습니다.
		require(game.price > 0);
		
		// 이미 구매한 경우에는 재구매할 수 없습니다.
		require(checkIsBuyer(msg.sender, gameId) != true);
		
		// 보유 DC량이 게임 가격보다 높아야 합니다.
		require(dplayCoin.balanceOf(msg.sender) >= game.price);
		
		// 구매자로 등록합니다.
		buyerToGameIds[msg.sender].push(gameId);
		gameIdToBuyers[gameId].push(msg.sender);
		
		// DC를 전송합니다.
		dplayCoin.transferFrom(msg.sender, game.publisher, game.price);
		
		emit Buy(gameId, msg.sender);
	}
	
	// 특정 주소가 구매자인지 확인합니다.
	function checkIsBuyer(address addr, uint gameId) public view returns (bool) {
		
		uint[] memory gameIds = buyerToGameIds[addr];
		for (uint i = 0; i < gameIds.length; i += 1) {
			if (gameIds[i] == gameId) {
				return true;
			}
		}
		
		return false;
	}
	
	// 게임을 평가합니다.
	function rate(uint gameId, uint rating, string calldata review) external {
		
		Game memory game = games[gameId];
		
		// 정상적인 게임 정보여야 합니다.
		require(game.publisher != address(0x0));
		
		// 유료 게임은 구매자만 평가할 수 있습니다.
		require(game.price == 0 || checkIsBuyer(msg.sender, gameId) == true);
		
		// 이미 평가한 경우에는 재평가할 수 없습니다.
		require(checkIsRater(msg.sender, gameId) != true);
		
		// 점수는 10점 이하여야 합니다.
		require(rating <= 10 * 10 ** uint(RATING_DECIMALS));
		
		// 평가를 등록합니다.
		gameIdToRatings[gameId].push(Rating({
			rater : msg.sender,
			rating : rating,
			review : review
		}));
		
		emit Rate(gameId, msg.sender, rating, review);
	}
	
	// 특정 주소가 평가자인지 확인합니다.
	function checkIsRater(address addr, uint gameId) public view returns (bool){
		
		Rating[] memory ratings = gameIdToRatings[gameId];
		for (uint i = 0; i < ratings.length; i += 1) {
			if (ratings[i].rater == addr) {
				return true;
			}
		}
		
		return false;
	}
	
	// 특정 평가자가 내린 평가 정보를 반환합니다.
	function getRating(address rater, uint gameId) external view returns (uint rating, string memory review) {
		
		Rating[] memory ratings = gameIdToRatings[gameId];
		for (uint i = 0; i < ratings.length; i += 1) {
			
			// 내가 내린 평가인 경우
			if (ratings[i].rater == rater) {
				return (
					ratings[i].rating,
					ratings[i].review
				);
			}
		}
	}
	
	// 평가를 수정합니다.
	function updateRating(uint gameId, uint rating, string calldata review) external {
		
		Rating[] storage ratings = gameIdToRatings[gameId];
		for (uint i = 0; i < ratings.length; i += 1) {
			
			// 평가자인 경우에만
			if (ratings[i].rater == msg.sender) {
				
				ratings[i].rating = rating;
				ratings[i].review = review;
				
				emit UpdateRating(gameId, msg.sender, rating, review);
				return;
			}
		}
	}
	
	// 평가를 삭제합니다.
	function removeRating(uint gameId) external {
		
		Rating[] storage ratings = gameIdToRatings[gameId];
		for (uint i = 0; i < ratings.length; i += 1) {
			
			// 평가자인 경우에만
			if (ratings[i].rater == msg.sender) {
				
				delete ratings[i];
				
				emit RemoveRating(gameId, msg.sender);
				return;
			}
		}
	}
	
	// 게임의 평가 수를 반환합니다.
	function getRatingCount(uint gameId) external view returns (uint) {
		return gameIdToRatings[gameId].length;
	}
	
	// 게임의 종합 평가 점수를 반환합니다.
	// 종합 평가 점수 = (모든 평가의 합: 평가자 A의 DC Power * 평가자 A의 평가 점수) / 모든 평가자의 DC Power
	function getOverallRating(uint gameId) external view returns (uint) {
		
		uint totalPower = 0;
		uint totalRating = 0;
		
		Rating[] memory ratings = gameIdToRatings[gameId];
		for (uint i = 0; i < ratings.length; i += 1) {
			if (ratings[i].rater != address(0x0)) {
				
				uint power = dplayCoin.getPower(ratings[i].rater);
				
				totalPower = totalPower.add(power);
				totalRating = totalRating.add(power.mul(ratings[i].rating));
			}
		}
		
		return totalPower == 0 ? 0 : totalRating.div(totalPower);
	}
}