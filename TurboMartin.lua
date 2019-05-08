-- Усреднятор фьючерсный
-- "Turbo Pascal" (с) 2019.

-- открывает сделку по пересечению MA.
-- На графике - только цена и МА. Суффиксы: (_Price и _MA)
-- Усреднение - CrossMA+StepSize.

ClientCode = "сюда своё" -- общий код для акций и фьючерсов.
SleepDuration = 10; -- отдыхаем 10 секунд. Слишком часто не надо молотить.
TickerCode = "SRM9";
ClassCode = "SPBFUT"
AccountCode = "сюда своё"
LotSize = 1
StepSize = 200
TakeSize = 200
TP=200
TRAIL=200
SL=100

-- Update 05.05.2019
MaxDrillDown = 5000
-- Параемтр MaxDrillDown указывает, сколько мы можем плить, набирая позу, максимум.
-- При превышении данной нормы, происходит немедленный сброс позиции (стоплосс),
-- и начинается поиск новой начальной точки входа.

PositionList = "c:\\TurboMartin\\Position.txt" -- здесь хранятся данные о позиции.
CurrentState = "c:\\TurboMartin\\CurrentState.txt" -- здесь хранятся данные о позиции.

LogFileName = "c:\\Log\\turbomartin_log.txt" -- Технический лог.

is_run=true

function main()
	while is_run do
		if HaveOpenPosition()==false then
			SetValueToFile(CurrentState, "MARTIN");
			SetValueToFile(PositionList, "");
		end
		
		aCurrentState = GetValueFromFile(CurrentState);
		if aCurrentState=="MARTIN" then
			-- Сначала получаем текущую цену.
			local CurrentPrice=GetLastPrice(TickerCode, "LAST");
			-- Теперь читаем таблицу сделок.
			
			--local PosList = LoadPositionList();		
			local f,err = io.open(PositionList,"r")
			if not f then
				return nil,err
			end
			
			LastPrice = 0;
			Summa = 0;
			NLot = 0;
			SummaMinus = 0;
			
			local PosList={};
			while true do
				local val = f:read("*l")
				if val == nil then break end
				NLot=NLot+1
				Summa = Summa+val;
				SummaMinus = SummaMinus+(val-CurrentPrice)
				PosList[NLot] = val;
				LastPrice = val;
			end
			f:close()
			
			if (MaxDrillDown>SummaMinus) then
				DoFire(CurrentPrice, "S", NLot)
				SetValueToFile(PositionList, "");
				SetValueToFile(CurrentState, "MARTIN");
			end
			
			if NLot>0 then
				Srednyaya = Summa/NLot;
			else
				Srednyaya=0;
			end
			WLOG("Sr="..Srednyaya.." Last="..LastPrice.." Curr="..CurrentPrice.." NLot="..NLot.." State="..aCurrentState);
			
			-- Ок, теперь выясняем где мы.
			if (Srednyaya>0) and (CurrentPrice>Srednyaya+TakeSize) then -- Если Выше средней на 200, то ставим трейл 200-200-100.
				DoTrailStop(CurrentPrice, "B", NLot, TP, TRAIL, SL)
				SetValueToFile(CurrentState, "TRAIL")
			end
			
			WLOG("Last-Step="..LastPrice-StepSize);
			
			if (CurrentPrice<(LastPrice-StepSize)) or (LastPrice==0) then
				-- Если ниже нижней на Stepsize, то можно ставить еще одну сделку. Либо открывать первую.
				WLOG("We are here");
				-- Но снавала проверяем простейший разворот - пересечение машки.
				if PriceCrossMAToUp(TickerCode) then
					DoFire(CurrentPrice, "B")
					-- Теперь добавляем в таблицу, и сохраняем на диск.
					PosList[NLot+1]=CurrentPrice;
					-- и сохраняем обновленный список.
					local l_file=io.open(PositionList, "w") -- используем "w", перезаписываем всё.
					for key, aaa in ipairs(PosList) do
					l_file:write(aaa.."\n")
					end
					l_file:close()
					SetValueToFile(CurrentState, "MARTIN");
				end;
			end
		end -- if aCurrentState==MARTIN
		
		sleep(SleepDuration*1000) -- Отдыхаем SleepDuration секунд.
	end
end

function GetLastPrice(TickerCode, CandleType)
	-- Берем цену из графика. CreateDataSource пока не используем, т.к. при необходимости модификации
	-- алгоритма, хотим легко добавлять индикаторы.
	-- Плюс меньше зависим от коннекта - графики всегда с нами.
	local NL=getNumCandles(TickerCode.."_Price")
	tL, nL, lL = getCandlesByIndex (TickerCode.."_Price", 0, NL-1, 1) -- last свеча
	local aCurrentPrice=tL[0].close -- получили текущую цену (ЦПС)
	if CandleType=="OPEN" then aCurrentPrice=tL[0].open end;
	if CandleType=="HIGH" then aCurrentPrice=tL[0].high end;
	if CandleType=="LOW" then aCurrentPrice=tL[0].low end;
	return aCurrentPrice
end

function GetMA(TickerCode)
	-- получаем текущие значения Боллинлжера.
	-- LineCode может иметь значения: "High", "Middle", "Low"
	local NbbL=getNumCandles(TickerCode.."_MA")
	tbbL, nbbL, lbbL = getCandlesByIndex (TickerCode.."_MA", 0, NbbL-1, 1)  -- last свеча, средняя линия Боллинджера
	MA = tbbL[0].close -- тек значение средней BB Local
	return MA;
end

function PriceCrossMAToUp(TickerCode)
	-- Функция возвращает TRUE, если пересекли среднюю линию Боллинджера снизу вверх
	if GetLastPrice(TickerCode, "OPEN")<GetMA(TickerCode)
		and GetLastPrice(TickerCode, "LAST")>GetMA(TickerCode)
	then return true
	else return false
	end;
end

function PriceCrossMAToDown(TickerCode)
	-- Функция возвращает TRUE, если пересекли среднюю линию Боллинджера снизу вверх
	if GetLastPrice(TickerCode, "OPEN")>GetMA(TickerCode)
		and GetLastPrice(TickerCode, "LAST")<GetMA(TickerCode)
	then return true
	else return false
	end;
end

function DoFire(p_price, p_dir) -- Функция - СДЕЛКА ПО РЫНКУ!
	if p_dir == "B" then AAA = 1 else AAA = -1 end
	t = {
			["CLASSCODE"]=ClassCode,
			["SECCODE"]=TickerCode,
			["ACTION"]="NEW_ORDER", -- новая сделка.
			["ACCOUNT"]=AccountCode,
			["CLIENT_CODE"]=ClientCode,
			["TYPE"]="L", -- "M" "L". По M давал ошибку на TQBR.
			["OPERATION"]=p_dir, -- направление сделки, "B" или "S"
			["QUANTITY"]=tostring(LotSize), -- объем, (акции - в лотах, а не штуках).
			["PRICE"]=tostring(p_price+(100*AAA)), -- цену лимитки ставим для мгновенного исполнения.
			["TRANS_ID"]="1"
		}
	
	res1 = sendTransaction(t) -- ... передаем сделку по рынку.
	
	if (res1~="") then -- Ошибочка вышла. Логируем ошибку.
		WLOG("SendTransaction Error = "..res1);
	end
	
	WLOG(os.date()..";SECCODE="..TickerCode..";PRICE="..p_price..";DIR="..p_dir.."\n")
		
	return res1
end

function DoTrailStop(p_price, p_dir, LotSize, TP, TRAIL, SL) -- "B" or "S" -- СДЕЛКА ПО РЫНКУ!!!

	WLOG("DoTrailStop. Start. p_dir="..p_dir..". p_price="..p_price)

	-- Здесь - три вспомогательных флага направления. Чтобы не писать отдельно для Лонг и Шорт.
	if p_dir == "B" then AAA = 1 else AAA = -1 end
	if p_dir == "B" then BBB = "S" else BBB = "B" end
	if p_dir == "B" then CCC = "4" else CCC = "5" end

	t_stop =
	{
		['ACTION'] = "NEW_STOP_ORDER", 
		['PRICE'] = tostring(p_price-(100*AAA)), -- меньше, проскальзывание
		['EXPIRY_DATE'] = "GTC",
		['STOPPRICE'] = tostring(p_price+(TP*AAA)), -- тейк
		['STOPPRICE2'] = tostring(p_price-(SL*AAA)), -- больше, срабатывание стопа
		['STOP_ORDER_KIND'] = "TAKE_PROFIT_AND_STOP_LIMIT_ORDER",
		['OFFSET'] = tostring(TRAIL),
		["OFFSET_UNITS"] = "PRICE_UNITS",
		["MARKET_TAKE_PROFIT"] = "YES",
		['TRANS_ID'] = "2",
		['CLASSCODE'] = ClassCode,
		['SECCODE'] = TickerCode,
		['ACCOUNT'] = AccountCode,
		['CLIENT_CODE'] = ClientCode, 
		['TYPE'] = "L", -- лимитка
		['OPERATION'] = BBB, -- направление стопа (обратное к сделке).
		['CONDITION'] = tostring(CCC), -- 4 или 5 ("меньше или равно" или "больше или равно") - направление стоп-цены.
		['QUANTITY'] = tostring(LotSize) -- кол-во контрактов
	}	
	res2 = sendTransaction(t_stop)
	WLOG("Результат выставления стопа (должно быть пусто) = '"..res2.."'")
   
	WLOG("DoTrailStop. End.") -- Пишем в лог, что эту контрольную точку прошли.
end

function GetValueFromFile(FileName) -- Читаем параметр из файла.
	local f = io.open(FileName, "r");
	if f == nil then -- если файла нет, но создаем пустой.
		f = io.open(FileName,"w");
		DefaultValueForFile = "MARTIN" -- по умолчанию пишем нуль.
		-- Для LastDirection надо бы писать не нуль, а "B", но пусть будет нуль, т.к.
		-- этого условия достаточно для открытия начальной сделки.
		f:write(DefaultValueForFile)
		f:close();
		-- Открывает уже гарантированно существующий файл в режиме "чтения/записи"
		f = io.open(FileName, "r");
	end;
	aValue = f:read("*l")
	f:close()
	return aValue
end

function SetValueToFile(FileName, aValue) -- Пишем параметр в файл.
	local ff=io.open(FileName, "w") -- используем "w", а не "a", чтобы перезаписать существующий.
	ff:write(aValue)
	ff:close()
end

function OnStop(stop_flag)
	is_run=false
end

function WLOG(st) -- Универсальная функция записи в лог.
	local l_file=io.open(LogFileName, "a") -- используем "a", чтобы добавить новую строку.
	l_file:write(os.date().." "..st.."\n")
	l_file:close()
end

function HaveOpenPosition() -- Возвращает TRUE, если есть открытая позиция по инструменту.
	for i = 0,getNumberOf("FUTURES_CLIENT_HOLDING") - 1 do
		if getItem("FUTURES_CLIENT_HOLDING",i).sec_code == TickerCode then
			if getItem("FUTURES_CLIENT_HOLDING",i).totalnet ~= 0 then
				return true
			else
				return false
			end
		end
	end
end
