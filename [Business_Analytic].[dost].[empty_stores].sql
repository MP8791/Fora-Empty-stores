declare @dat date=cast(getdate() as date)
--declare @start_dat date=dateadd(day, -56, @dat)
declare @start_dat_vozvrat date=dateadd(day, -56, @dat)


-- declare @dat date='2026-04-24' declare @filid int=21
drop table if exists #stores_dwh --залишки двх, звичайний товар
select p.lagerid, p.filid, sum(p.kolvo) kolvo_fact
into #stores_dwh 
from DataWareHouse..view_stores p
join CB.dbo.Lager lg on lg.id=p.LagerId and lg.typeId in (1,9)
where operationdate=@dat --and p.filid=@filid
group by p.lagerid, p.filid

-- declare @dat date='2026-04-24' declare @filid int=21
drop table if exists #stores_assort --зводимо в таблицю всі товари з залишком і товари з довідника статусів
select l.filid,l.lagerid, isnull(dwh.kolvo_fact,0) store_kolvo, l.[SAPStatus], t.Remark, cast(l.modified as date) assort_modified
into #stores_assort
from [CB].[dbo].[LagerAssortiment] l 
join CB.dbo.Lager lg on lg.id=l.LagerId and lg.typeId in (1,9)
left join [CB].[dbo].[TypeSAPStatusAssortiment] t on t.[SAPStatus]=l.[SAPStatus]
left join #stores_dwh dwh on dwh.FILID=l.filId and dwh.LAGERID=l.LagerId
left join masterdata..dim_filials f on f.[fil.Filials.filialId]=l.filid
where isnull(dwh.kolvo_fact,0)<=0 and (f.[fil.Filials.filialNameUA] like 'Д %' or f.[fil.Filials.filialNameUA] like 'Л %' or f.[fil.Filials.filialNameUA] like 'Р %')

-- declare @dat date='2026-04-24' declare @filid int=21
drop table if exists #logismotv  --вік карточки товару в кожному магазині для подальшого відокремлення нових позицій
select distinct z.filid, z.lagerid, z.dateopen, z.[card_status], z.card_age
into #logismotv
from [DBMS_Zelinskaya].[Zelinskaya].[dbo].[logismotv] z
where z.dat=@dat 

-- declare @dat date='2026-04-24' declare @filid int=21
drop table if exists #base
select 
    c.*, 
    cast(z.dateopen as date) as dateopen, 
    z.card_status, 
    z.card_age
into #base
from #stores_assort c
left join #logismotv z on z.filid = c.filId and z.lagerid = c.LagerId
  where c.SAPStatus is null or c.SAPStatus not in ('BP','BA','BS','DL')

--ДОГОВОРИ ПОСТАВКИ У МАГАЗИН
-- declare @dat date='2026-04-24' declare @filid int=21
		drop table if exists #dogov0
		SELECT     #base.filId,#base.LagerId,h.SAPID AS [№ договора], h.PostavshikID AS PostID,
									--ISNULL(CAST(sch.day1 AS int), 0) AS ПН, ISNULL(CAST(sch.day2 AS int), 0) AS ВТ, ISNULL(CAST(sch.day3 AS int), 0) AS СР, 
									--ISNULL(CAST(sch.day4 AS int), 0) AS ЧТ, ISNULL(CAST(sch.day5 AS int), 0) AS ПТ, ISNULL(CAST(sch.day6 AS int), 0) AS СБ, 
									--ISNULL(CAST(sch.day7 AS int), 0) AS ВС, 
									sch.DeltaForDelivery AS [Дней до поставки], sch.deltaFilialFromRC, sch.Frequency AS Частота, 
									sch.DateSt AS [Дата начала], sch.CoefSale AS [Dogovor_coef], '' AS ' ', RTrim(CB.dbo.Adress.Name) AS Поставщик
									,df.[fil.Filials.filialId] [FilidRC_dogov], h.DateFinish
									,dateadd(day,-iif(frequency >= 2, datediff(day, sch.DateSt, cast(getdate() as DATE)) % (frequency * 7), 0),cast(getdate()-sch.DeltaForDelivery as DATE))  ddd
			into #dogov0
			FROM          CB.dbo.DogovorHeader AS h WITH (nolock) 
			JOIN CB.dbo.DogovorFilials  ON h.ID = CB.dbo.DogovorFilials.DogovorID 
			JOIN CB.dbo.FilialMail WITH (nolock) ON CB.dbo.DogovorFilials.FilID = CB.dbo.FilialMail.id 
			JOIN CB.dbo.Adress  ON h.PostavshikID = CB.dbo.Adress.ID 
			join [CB].[dbo].[DogovorArticles] a on a.DogovorID=h.id
			LEFT JOIN CB.dbo.DogovorSchedule AS sch  ON CB.dbo.DogovorFilials.FilID = sch.FilID AND h.ID = sch.DogovorID 
			join #base on #base.filId=CB.dbo.DogovorFilials.FilID and #base.LagerId=a.LagerID
			left join MasterData.dbo.dim_Filials df on df.[Contragents.contragentId]=h.PostavshikID
			WHERE cast(h.DateBegin as DATE) <= cast(GETDATE() + 1 as date) and sch.DeltaForDelivery is not null

		-- (418 rows affected) 00:01
		drop table if exists #dogov
		select d.*
		,ROW_NUMBER() over (partition by filid, lagerid order by [DateFinish] desc, [Dogovor_coef] desc) rn
		into #dogov
		from #dogov0 d		
--КІНЕЦЬ БЛОКУ ДОГОВОРІВ ПОСТАВКИ У МАГАЗИН

--ДОГОВОРИ ПОСТАВКИ У РЦ
drop table if exists #dogov0_RC2
SELECT     dg.FilidRC_dogov,dg.LagerId,h.SAPID AS [№ договора], h.PostavshikID AS PostID,
                            --ISNULL(CAST(sch.day1 AS int), 0) AS ПН, ISNULL(CAST(sch.day2 AS int), 0) AS ВТ, ISNULL(CAST(sch.day3 AS int), 0) AS СР, 
                            --ISNULL(CAST(sch.day4 AS int), 0) AS ЧТ, ISNULL(CAST(sch.day5 AS int), 0) AS ПТ, ISNULL(CAST(sch.day6 AS int), 0) AS СБ, 
                            --ISNULL(CAST(sch.day7 AS int), 0) AS ВС
							sch.DeltaForDelivery AS [Дней до поставки], sch.deltaFilialFromRC, sch.Frequency AS Частота, 
                            sch.DateSt AS [Дата начала], h.DateFinish, sch.CoefSale AS [Dogovor_coef], '' AS ' ', RTrim(CB.dbo.Adress.Name) AS Поставщик
							
    into #dogov0_RC2
	FROM CB.dbo.DogovorHeader AS h WITH (nolock)
	JOIN CB.dbo.DogovorFilials  ON h.ID = CB.dbo.DogovorFilials.DogovorID 
	JOIN CB.dbo.FilialMail WITH (nolock) ON CB.dbo.DogovorFilials.FilID = CB.dbo.FilialMail.id 
	JOIN CB.dbo.Adress  ON h.PostavshikID = CB.dbo.Adress.ID 
	inner join [CB].[dbo].[DogovorArticles] a on a.DogovorID=h.id
	LEFT JOIN CB.dbo.DogovorSchedule AS sch  ON CB.dbo.DogovorFilials.FilID = sch.FilID AND h.ID = sch.DogovorID 	
	join  #dogov dg on dg.FilidRC_dogov=CB.dbo.DogovorFilials.FilID and dg.LagerId=a.LagerID		
    WHERE cast(h.DateBegin as DATE) <= cast(GETDATE() + 1 as date)	 and sch.DeltaForDelivery is not null

-- (217626 rows affected) 00:00
	drop table if exists #dogov_RC2
	select d.*
	,ROW_NUMBER() over (partition by FilidRC_dogov, lagerid order by [DateFinish] desc, [Dogovor_coef] desc) rn
	into #dogov_RC2
	from #dogov0_RC2 d
--КІНЕЦЬ БЛОКУ ДОГОВОРІВ ПОСТАВКИ У РЦ
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

--///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--БЛОК КРАЙНІЙ ЗАКАЗ НА МАГАЗИН, ЩО МАВ ПРИЇХАТИ------
drop table if exists #zakaz64_1
select z.FilId,z.LagerID, max(z.DateToPost) DateToPost
into #zakaz64_1
from business_analytic.utz.zakaz_64server z
join #base b on b.filId=z.FilId and b.LagerId=z.LagerID
where z.DateToPost<@dat 
group by z.FilId,z.LagerID,z.PostavshikID

--БЕРЕМО ДАНІ З КРАЙНЬОГО ЗАКАЗУ
drop table if exists #zakaz64_4
select c.filid, c.lagerid, c.Status,c.RealTypeZakaz, c.TypeID,  max(c.created) created, c.DateToPost,c.PostavshikID
		,sum(c.Kolvo) kolvo,sum(c.KolvoFirst) KolvoFirst
		,k.[Contragents.FullName]
		,case when k.[Contragents.businessId]=4 then k.[Contragents.InternalFilial] else 0 end [Contragents.InternalFilial]
		,f.[fil.Filials.filialId] FILID_RC
		,c.[Orders_short_type_id]
into #zakaz64_4
from business_analytic.utz.zakaz_64server c
join (select z.FilId,z.LagerID, datetopost
		,row_number() OVER(PARTITION BY z.filid, z.lagerid Order by datetopost desc) rn
		from #zakaz64_1 z) z on z.FilId=c.FilId and z.LagerID=c.LagerID and z.DateToPost=c.DateToPost and z.rn=1
join MasterData.dbo.dim_Contragents k on k.[Contragents.ContragentId]=c.PostavshikID
left join MasterData.dbo.dim_Filials f on f.[Contragents.ContragentId]=c.PostavshikID
group by 
c.filid, c.lagerid, c.Status,c.RealTypeZakaz, c.TypeID, c.DateToPost,c.PostavshikID,k.[Contragents.FullName]
,case when k.[Contragents.businessId]=4 then k.[Contragents.InternalFilial] else 0 end
,f.[fil.Filials.filialId],c.[Orders_short_type_id]
----кінець блоку КРАЙНІЙ ЗАКАЗ НА МАГАЗИН, ЩО МАВ ПРИЇХАТИ------

----беремо закази не з статусом "проведено"
drop table if exists #zakaz64_1_storned--беремо крайні закази з business_analytic.utz.zakaz_64server
select z.FilId,z.LagerID, [Status],z.PostavshikID, max(z.DateToPost) DateToPost
into #zakaz64_1_storned
from business_analytic.utz.zakaz_64server_other_status z
join #base b on b.filId=z.FilId and b.LagerId=z.LagerID
where z.DateToPost<@dat 
group by z.FilId,z.LagerID, [Status],z.PostavshikID

-- declare @dat date='2026-04-24'
drop table if exists #zakaz64_storned
select c.filid, c.lagerid, c.Status,c.RealTypeZakaz, c.TypeID, max(c.created) created, c.DateToPost,c.PostavshikID
		,sum(c.Kolvo) kolvo,sum(c.KolvoFirst) KolvoFirst
		,k.[Contragents.FullName]
		,case when k.[Contragents.businessId]=4 then k.[Contragents.InternalFilial] else 0 end [Contragents.InternalFilial]
		,f.[fil.Filials.filialId] FILID_RC
		,null [Orders_short_type_id]
into #zakaz64_storned
from business_analytic.utz.zakaz_64server_other_status c
join (select z.FilId,z.LagerID, datetopost, [Status]
		,row_number() OVER(PARTITION BY z.filid, z.lagerid Order by datetopost desc) rn
		from #zakaz64_1_storned z) z on z.FilId=c.FilId and z.LagerID=c.LagerID and z.DateToPost=c.DateToPost and z.rn=1
join MasterData.dbo.dim_Contragents k on k.[Contragents.ContragentId]=c.PostavshikID
left join MasterData.dbo.dim_Filials f on f.[Contragents.ContragentId]=c.PostavshikID
group by 
c.filid, c.lagerid, c.Status,c.RealTypeZakaz, c.TypeID, c.DateToPost,c.PostavshikID,k.[Contragents.FullName]
,case when k.[Contragents.businessId]=4 then k.[Contragents.InternalFilial] else 0 end
, f.[fil.Filials.filialId]
----кінець блоку заказів з business_analytic.utz.zakaz_64server ТА СТАТУСОМ <> ПРОВЕДЕНО

--вибираємо крайній заказ на магазин незалежно від статусу
drop table if exists #zakaz64
select x.*
into #zakaz64 from (
select c.*
,row_number() over (partition by filid,lagerid order by DateToPost desc, [Status] asc ) rn
from (	SELECT * FROM #zakaz64_4
		UNION ALL
		SELECT * FROM #zakaz64_storned) c ) x
where rn=1
--кінець блоку "вибираємо крайній заказ на магазин незалежно від статусу"
--///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--початок блоку "КРАЙНІЙ ЗАКАЗ НА РЦ (статус проведено) - крайня поставка на РЦ до дати створення заказу на магазин ТІЛЬКИ ДЛЯ ЗБЕРІГАННЯ
-- беремо артикул/рц/дата створення заказу в магазин
drop table if exists #zakazRC_0
select Lagerid, filid_RC, z.Created Created_shop /*, z.DateToPost DateToPost_shop */
into #zakazRC_0 
from #zakaz64 z
where z.RealTypeZakaz=0  --not (z.RealTypeZakaz=1 and FILID_RC=4068)

--крайній заказ на РЦ перед поставкой в магазин (статус 3 - проведено)
drop table if exists #zakazRC_1
select b.filid_RC FilId,b.LagerID, b.Created_shop, max(z.DateToPost) DateToPost
into #zakazRC_1
from #zakazRC_0 b
join business_analytic.utz.zakaz_64server z  on b.FILID_RC=z.FilId and b.LagerId=z.LagerID and b.Created_shop>z.DateToPost
group by b.filid_RC,b.LagerID,b.Created_shop

drop table if exists #zakazRC_2
select distinct c.FilId,c.LagerID, c.DateToPost into #zakazRC_2 from #zakazRC_1 c

drop table if exists #zakazRC64
select c.filid, c.lagerid, max(c.created) created, c.DateToPost, max(c.PostavshikID) PostavshikID,sum(c.Kolvo) kolvo,sum(c.KolvoFirst) KolvoFirst
into #zakazRC64
from business_analytic.utz.zakaz_64server c
join #zakazRC_2 z on z.FilId=c.FilId and z.LagerID=c.LagerID and z.DateToPost=c.DateToPost
group by c.filid, c.lagerid, c.DateToPost

drop table if exists #zakazRC64_modif
select r.filid, r.lagerid, r.created, r.DateToPost,r.PostavshikID,r.kolvo,r.KolvoFirst,c.Created_shop
into #zakazRC64_modif
from #zakazRC_1 c
join #zakazRC64 r on r.FilId=c.FilId and r.LagerID=c.LagerID and r.DateToPost=c.DateToPost
--КІНЕЦЬ блоку "КРАЙНІЙ ЗАКАЗ НА РЦ (статус проведено) - крайня поставка на РЦ до дати створення заказу на магазин ТІЛЬКИ ДЛЯ ЗБЕРІГАННЯ




--початок блоку "КРАЙНІЙ ЗАКАЗ НА РЦ (статус проведено) - крайня поставка на РЦ до дати створення заказу на магазин НЕ ДЛЯ ЗБЕРІГАННЯ (КРІМ ДИСТР СКОРОПОРТУ)
-- беремо артикул/рц/дата створення заказу в магазин
drop table if exists #zakazRC_0_d
select Lagerid, filid_RC, z.DateToPost DateToPost_shop /*, z.DateToPost DateToPost_shop */
into #zakazRC_0_d
from #zakaz64 z
where z.RealTypeZakaz<>0  and not (z.RealTypeZakaz=1 and FILID_RC=4068)

--крайній заказ на РЦ перед поставкой в магазин (статус 3 - проведено)
drop table if exists #zakazRC_1_d
select b.filid_RC FilId,b.LagerID, b.DateToPost_shop, max(z.DateToPost) DateToPost
into #zakazRC_1_d
from #zakazRC_0_d b
join business_analytic.utz.zakaz_64server z  on b.FILID_RC=z.FilId and b.LagerId=z.LagerID and b.DateToPost_shop>z.DateToPost
group by b.filid_RC,b.LagerID,b.DateToPost_shop

drop table if exists #zakazRC_2_d
select distinct c.FilId,c.LagerID, c.DateToPost into #zakazRC_2_d from #zakazRC_1_d c

drop table if exists #zakazRC64_d
select c.filid, c.lagerid, max(c.created) created, c.DateToPost, max(c.PostavshikID) PostavshikID,sum(c.Kolvo) kolvo,sum(c.KolvoFirst) KolvoFirst
into #zakazRC64_d
from business_analytic.utz.zakaz_64server c
join #zakazRC_2_d z on z.FilId=c.FilId and z.LagerID=c.LagerID and z.DateToPost=c.DateToPost
group by c.filid, c.lagerid, c.DateToPost

drop table if exists #zakazRC64_modif_d
select r.filid, r.lagerid, r.created, r.DateToPost,r.PostavshikID,r.kolvo,r.KolvoFirst,c.DateToPost_shop
into #zakazRC64_modif_d
from #zakazRC_1_d c
join #zakazRC64_d r on r.FilId=c.FilId and r.LagerID=c.LagerID and r.DateToPost=c.DateToPost

--КІНЕЦЬ блоку "КРАЙНІЙ ЗАКАЗ НА РЦ (статус проведено) - крайня поставка на РЦ до дати створення заказу на магазин НЕ ДЛЯ ЗБЕРІГАННЯ (КРІМ ДИСТР СКОРОПОРТУ)


--початок блоку "КРАЙНІЙ ЗАКАЗ НА РЦ (для всіх заказів дистриб'юції скоропорту)  - крайня поставка на РЦ до дати поставки заказу на магазин виключно для ДИСТР СКОРОПОРТУ
-- беремо закази на РЦ з business_analytic.utz.zakaz_64server
drop table if exists #zakazRC_0_skor
select Lagerid, filid_RC, z.DateToPost  DateToPost_shop/*, z.DateToPost DateToPost_shop */
into #zakazRC_0_skor
from #zakaz64 z
where z.RealTypeZakaz=1 and FILID_RC=4068

--крайній заказ на РЦ перед поставкой в магазин (статус 3 - проведено)
drop table if exists #zakazRC_1_skor
select b.filid_RC FilId,b.LagerID, b.DateToPost_shop, max(z.DateToPost) DateToPost
into #zakazRC_1_skor
from #zakazRC_0_skor b
join business_analytic.utz.zakaz_64server z  on b.FILID_RC=z.FilId and b.LagerId=z.LagerID and b.DateToPost_shop>=z.DateToPost
group by b.filid_RC,b.LagerID,b.DateToPost_shop

drop table if exists #zakazRC_2_skor
select distinct c.FilId,c.LagerID, c.DateToPost into #zakazRC_2_skor from #zakazRC_1_skor c

drop table if exists #zakazRC64_skor
select c.filid, c.lagerid, max(c.created) created, c.DateToPost ,max(c.PostavshikID) PostavshikID,sum(c.Kolvo) kolvo,sum(c.KolvoFirst) KolvoFirst
into #zakazRC64_skor
from business_analytic.utz.zakaz_64server c
join #zakazRC_2_skor z on z.FilId=c.FilId and z.LagerID=c.LagerID and z.DateToPost=c.DateToPost
group by c.filid, c.lagerid, c.DateToPost

drop table if exists #zakazRC64_skor_modif
select r.filid, r.lagerid, r.created, r.DateToPost,r.PostavshikID,r.kolvo,r.KolvoFirst,c.DateToPost_shop
into #zakazRC64_skor_modif
from #zakazRC_1_skor c
join #zakazRC64_skor r on r.FilId=c.FilId and r.LagerID=c.LagerID and r.DateToPost=c.DateToPost

--КІНЕЦЬ блоку "КРАЙНІЙ ЗАКАЗ НА РЦ (статус проведено) - крайня поставка на РЦ до дати поставки заказу на магазин виключно для ДИСТР СКОРОПОРТУ
--///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

--ДОДАЄМО ДАНІ В #zakazRC64 ДАНИМИ З #zakazRC64_skor
	insert into #zakazRC64
	select c.*
	from #zakazRC64_skor c

	insert into #zakazRC64
	select d.*
	from #zakazRC64_d d
--КІНЕЦЬ ЗАМІНИ ДАНИХ В #zakazRC64 ДАНИМИ З #zakazRC64_skor_d


--БЛОК КРАЙНІЙ ЗАКАЗ НА МАГАЗИН, ЩО ЇДЕ------
	drop table if exists #zakaz64_1_way--беремо крайні закази з business_analytic.utz.zakaz_64server
	select z.FilId,z.LagerID, max(z.DateToPost) DateToPost
	into #zakaz64_1_way
	from business_analytic.utz.zakaz_64server z
	join #base b on b.filId=z.FilId and b.LagerId=z.LagerID
	where z.DateToPost>=@dat and z.Created<=@dat
	group by z.FilId,z.LagerID,z.PostavshikID

	--БЕРЕМО ДАНІ З КРАЙНЬОГО ЗАКАЗУ
	drop table if exists #zakaz64_4_way
	select c.*
	into #zakaz64_4_way
	from business_analytic.utz.zakaz_64server c
	join (select z.FilId,z.LagerID, datetopost
			,row_number() OVER(PARTITION BY z.filid, z.lagerid Order by datetopost desc) rn
			from #zakaz64_1_way z) z on z.FilId=c.FilId and z.LagerID=c.LagerID and z.DateToPost=c.DateToPost and z.rn=1
----кінець блоку КРАЙНІЙ ЗАКАЗ НА МАГАЗИН, ЩО ЇДЕ--------

---ПОЧАТОК БЛОКУ РАХУЄМО ІНШІ РУХИ ТОВАРУ З ДАТИ СТВОРЕННЯ ЗАКАЗУ (КРІМ ПОСТАВКИ І СПИСАННЯ/ПЕРЕОБЛІКІВ)
	drop table if exists #others_mov
	select [operationDate]
		  ,[filID]
		  ,[lagerID]
		  ,[operationID]
		  ,[operationKolvo]
	into #others_mov
	from [DataWareHouse].[dbo].[cache_FMF_Oper]
	where [operationDate] between @start_dat_vozvrat and @dat --and filid=@filid 

	drop table if exists #sum_others_mov
	select c.filid, c.lagerid, sum(c.[operationKolvo]) kolvo
	into #sum_others_mov
	from #others_mov c
	join #zakaz64 z on z.FilId=c.FilId and z.LagerID=c.LagerId
	where c.[operationDate] between z.Created and dateadd(day,-1,@dat)
		 and c.operationID in (6,8,13,15,16,17,30,32,33,51,52,53,54,55,56,57,58,61,62)
	group by c.filid, c.lagerid
---КІНЕЦЬ БЛОКУ РАХУЄМО ІНШІ РУХИ ТОВАРУ З ДАТИ СТВОРЕННЯ ЗАКАЗУ (КРІМ ПОСТАВКИ І СПИСАННЯ/ПЕРЕОБЛІКІВ)

drop table if exists #sl
select sl.DateToPost, sl.lagerid, sl.filid, sl.PostavshikID, sum(KOLVO_ZAKAZ) KOLVO_ZAKAZ, SUM (KOLVO_POST) KOLVO_POST 
into #sl
from [Business_Analytic].[utz].[SL] sl
join #zakaz64 zrc on sl.filid=zrc.FilId and sl.lagerid=zrc.LagerID and sl.DateToPost=zrc.DateToPost and sl.PostavshikID=zrc.PostavshikID 
group by sl.DateToPost, sl.lagerid, sl.filid, sl.PostavshikID

drop table if exists #slrc
select slrc.DateToPost, slrc.lagerid, slrc.filid, slrc.PostavshikID, sum(KOLVO_ZAKAZ) KOLVO_ZAKAZ, SUM (KOLVO_POST) KOLVO_POST 
into #slrc
from [Business_Analytic].[utz].[SL] slrc
join #zakazRC64 zrc on slrc.filid=zrc.FilId and slrc.lagerid=zrc.LagerID and slrc.DateToPost=zrc.DateToPost and slrc.PostavshikID=zrc.PostavshikID 
group by slrc.DateToPost, slrc.lagerid, slrc.filid, slrc.PostavshikID

--declare @dat date='2026-04-24'
drop table if exists #vtr
select c.filid, c.Lagerid,  SUM(c.kolvo) vtrati 
into #vtr
from Business_Analytic.poteri.IIImes c
join #zakaz64 z on z.FilId=c.Filid and z.LagerID=c.lagerid
where c.Operdate between z.Created and dateadd(day,-1,@dat)
group by c.filid, c.Lagerid

drop table if exists #fora_import
SELECT distinct [lagerid] 
into #fora_import
FROM [Business_Analytic].[dbo].[rostim_new] 
where YEAR=YEAR(@dat) and MONTH=month(@dat) and [store_rostim_finish_kolvo]<>0

drop table if exists #silpo_import
select  distinct([lagerId]) 
into #silpo_import
from [MasterData].[sku].[Lagers] 
where [lagerOwnImport]=1 and lagerMacroID<>27 


--declare @dat date=cast(getdate() as date)
drop table if exists #base1
select @dat [date],b.filId, b.LagerId
,b.store_kolvo,b.SAPStatus,b.Remark, b.assort_modified  --,b.created,
,b.dateopen, b.[card_status], b.card_age
,z_way.Created [Заказ в путі: Created],z_way.DateToPost [Заказ в путі: DateToPost],z_way.Kolvo [Заказ в путі: довідково Kolvo]
,z.Created,z.DateToPost--,z.SapCounter
,z.RealTypeZakaz, rlt.descriptionSmall [дистриб'юція/зберігання]
,zt.descriptionSmall [тип створення заказу]
,z.Status, stat.[descriptionFull] [статус заказу]
,z.KolvoFirst,z.Kolvo, z.PostavshikID,z.[Contragents.FullName], z.[Contragents.InternalFilial]
,case when sl.KOLVO_ZAKAZ is null and z.Created is not null then 0 else sl.KOLVO_ZAKAZ end KOLVO_ZAKAZ
,case when sl.KOLVO_POST is null and z.Created is not null then 0 else sl.KOLVO_POST end KOLVO_POST
,uuu.[last_date_store] [крайня дата з залишком на магазині],st.KOLVO [Залишок на магазині на дату створення заказу на маг.]
,vtr.vtrati [Списання/переобліки з дати створення заказу на маг.]
,voz.kolvo [Інші рухи з дати створення заказу на маг.]
,case when z.FILID_RC is null then f2.[fil.Filials.filialId] else z.FILID_RC end FILID_RC   
, la.SAPStatus [SAPStatus_RC], cast(la.modified as date) [modified_RC],t.Remark 'Remark_RC'
,st_rc_created.KOLVO [Залишок на РЦ на дату створення заказу на маг.]
,st_rc_datetopost.KOLVO [Залишок на РЦ на дату поставки у магазин]
,strc.store [Залишок на РЦ на дату розрахунку]

,case	when zrc.Created is not null then zrc.Created
		when zrc_d.Created is not null then zrc_d.Created else zrc_skor.Created end  Created_RC
,case	when zrc.DateToPost is not null then zrc.DateToPost 
		when zrc_d.DateToPost is not null then zrc_d.DateToPost else zrc_skor.DateToPost end  DateToPost_RC
,case	when zrc.PostavshikID is not null then zrc.PostavshikID 
		when zrc_d.PostavshikID is not null then zrc_d.PostavshikID else zrc_skor.PostavshikID end  PostavshikID_external
,case	when zrc.Kolvo is not null then zrc.Kolvo 
		when zrc_d.Kolvo is not null then zrc_d.Kolvo else zrc_skor.Kolvo end  Kolvo_RC
,case	when zrc.KolvoFirst is not null then zrc.KolvoFirst 
		when zrc_d.KolvoFirst is not null then zrc_d.KolvoFirst else zrc_skor.KolvoFirst end  KolvoFirst_RC

,case	when slrc.KOLVO_ZAKAZ is null then slrc_skor.KOLVO_ZAKAZ 
		else slrc.KOLVO_ZAKAZ end KOLVO_ZAKAZ_RC
,case	when slrc.KOLVO_POST is null then slrc_skor.KOLVO_POST 
		else slrc.KOLVO_POST end KOLVO_POST_RC

,case	when fora_import.LAGERID is not null then 'ВІ_Фора'
		when silpo_import.LAGERID is null then 'інше' else 'ВІ_Сільпо' end [Імпорт]
,dg.ddd [дата крайньої поставки кратно дню старту договору]
,z.[Orders_short_type_id]
into #base1
from #base b
join CB.dbo.Lager l on l.id=b.lagerid
left join #zakaz64 z on z.FilId=b.FilId and z.LagerID=b.LagerId
left join #zakaz64_4_way z_way on z_way.FilId=b.FilId and z_way.LagerID=b.LagerId
			--and z_way.DateToPost=z.DateToPost and z_way.PostavshikID=z.PostavshikID
left join #sl sl on sl.filid=z.FilId and sl.lagerid=z.LagerID and sl.DateToPost=z.DateToPost
			and sl.PostavshikID=z.PostavshikID
left join [CB].[dbo].[LagerAssortiment] la on la.LagerId=z.LagerId and la.filId=z.FILID_RC
left join [CB].[dbo].[TypeSAPStatusAssortiment] t on t.[SAPStatus]=la.[SAPStatus]
left join #zakazRC64_modif zrc on zrc.FilId=z.FILID_RC and zrc.LagerID=z.LagerID AND zrc.Created_shop=z.created
left join #zakazRC64_modif_d zrc_d on zrc_d.FilId=z.FILID_RC and zrc_d.LagerID=z.LagerID AND zrc_d.DateToPost_shop=z.DateToPost
left join #zakazRC64_skor_modif zrc_skor on zrc_skor.FilId=z.FILID_RC and zrc_skor.LagerID=z.LagerID AND zrc_skor.DateToPost_shop=z.DateToPost
left join #slrc slrc on slrc.filid=zrc.FILID and slrc.lagerid=zrc.LagerID 
			and slrc.DateToPost=zrc.DateToPost and slrc.PostavshikID=zrc.PostavshikID 
left join #slrc slrc_d on slrc_d.filid=zrc_d.FILID and slrc_d.lagerid=zrc_d.LagerID 
			and slrc_d.DateToPost=zrc_d.DateToPost and slrc_d.PostavshikID=zrc_d.PostavshikID 
left join #slrc slrc_skor on slrc_skor.filid=zrc_skor.FILID and slrc_skor.lagerid=zrc_skor.LagerID 
			and slrc_skor.DateToPost=zrc_skor.DateToPost and slrc_skor.PostavshikID=zrc_skor.PostavshikID 
join MasterData.dbo.dim_Filials f on f.[fil.Filials.filialId]=b.filId
left join DataWareHouse..view_stores st on st.FILID=z.filId and st.LAGERID=z.LagerId and st.STOREID=19 and st.OPERATIONDATE=z.Created
left join (select filid,Lagerid,SUM(kolvo) store from DataWareHouse..view_stores where OPERATIONDATE=@dat
			group by filid,Lagerid) strc on strc.FILID=z.FILID_RC and strc.LAGERID=z.LagerID
left join (select OPERATIONDATE,filid,Lagerid,SUM(kolvo) kolvo from DataWareHouse..view_stores
			group by OPERATIONDATE,filid,Lagerid) st_rc_created on st_rc_created.FILID=z.FILID_RC and st_rc_created.LAGERID=z.LagerId and st_rc_created.OPERATIONDATE=z.Created
left join (select OPERATIONDATE,filid,Lagerid,SUM(kolvo) kolvo from DataWareHouse..view_stores
			group by OPERATIONDATE,filid,Lagerid) st_rc_datetopost on st_rc_datetopost.FILID=z.FILID_RC and st_rc_datetopost.LAGERID=z.LagerId and st_rc_datetopost.OPERATIONDATE=z.Created
left join [Business_Analytic].[dost].[store_last_date] uuu on uuu.FILID=b.filId and uuu.LAGERID=b.LagerId
left join #vtr vtr on vtr.Filid=z.filId and vtr.lagerid=z.LagerId
left join #fora_import fora_import on fora_import.lagerId=b.LagerId----- власний імпорт Фора
left join #silpo_import silpo_import on silpo_import.lagerId=b.LagerId
left join #sum_others_mov voz on voz.filid=b.filid and voz.lagerid=b.lagerid 
left join [Business_Analytic].[utz].[zakaz_ZakazStatus] stat on stat.[id]=z.Status
left join [Business_Analytic].[utz].[zakaz_ZakazRealType] rlt on rlt.[id]=z.RealTypeZakaz
left join [Business_Analytic].[utz].[zakaz_ZakazType] zt on zt.id=z.TypeID
left join #dogov dg on dg.filId=b.filId and dg.LagerId=b.LagerId and dg.rn=1
left join [MasterData].[dbo].[dim_Filials] f2 on f2.[Contragents.ContragentId]=dg.PostID and dg.rn=1
where l.MacroID not in (72,78) and (f.[fil.Filials.filialNameUA] like 'Д %' or f.[fil.Filials.filialNameUA] like 'Л %') --or f.[fil.Filials.filialNameUA] like 'Р %'
--where filId=1738
--КРАЙНІ ДАТИ З ЗАЛИШКОМ НА РЦ
--declare @dat date='2026-04-24'

drop table if exists #dwh_RC
select c.FILID,c.LAGERID,MAX(operationdate) maxdate
into #dwh_RC
from DataWareHouse..view_stores c
join #base1 b on b.FILID_RC=c.FILID and c.LAGERID=b.LagerId
where operationdate between dateadd(day,-365,@dat) and @dat and c.Kolvo>0
group by c.FILID,c.LAGERID

--КРАЙНІй заказ НА РЦ
--declare @dat date='2026-04-24'
drop table if exists #dwh_RC_zakaz

select c.FILID,c.LAGERID, MAX(c.DateToPost) maxdate_zakazRC
into #dwh_RC_zakaz
from [Business_Analytic].[utz].[zakaz_64server] c
join #base1 b on b.FILID_RC=c.FILID and c.LAGERID=b.LagerId
where c.DateToPost between dateadd(day,-365,@dat) and dateadd(day,-1,@dat)
group by c.FILID,c.LAGERID


--дані щодо першої поставки на РЦ
drop table if exists #RC_first_shipment
SELECT c.[filid],c.[lagerid],c.[DateToPost]
	  ,ROW_NUMBER() over (partition by c.filid, c.lagerid order by c.datetopost asc) rn
	  into #RC_first_shipment
  FROM [Business_Analytic].[utz].[SL] c
 join (select distinct lagerid, FILID_RC from #base1) b on b.FILID_RC=c.filid and b.LagerId=c.lagerid
 where c.datetopost>GETDATE()-365
 --кінець блоку щодо першої поставки на РЦ


--declare @dat date=cast(getdate() as date)
drop table if exists #fin
select 
b.date [Дата з нульовими залишками]
,b.filId,f.[fil.Filials.filialNameUA] [filialName]
,b.LagerId, lc.FullName,lc.MacroID,lc.macroName, l.typeId [lager typeid]
,d.Dep_name
,case when d.Dep_group like 'стеллажка%' then 'Стелажка' else 'Скоропорт' end [Група]
,b.store_kolvo [Залишок на дату розрахунку, од.]
,b.dateopen, b.[card_status], b.card_age
,b.[Крайня дата з залишком на магазині],datediff(day,b.[Крайня дата з залишком на магазині],@dat) [Cкільки днів немає залишку товару в маг.]
,b.SAPStatus,b.Remark, b.assort_modified--,b.created

,b.[Created] [Крайній заказ: Created],b.[DateToPost] [Крайній заказ: DateToPost]
,b.[Заказ в путі: Created],b.[Заказ в путі: DateToPost],b.[Заказ в путі: довідково Kolvo]

,b.[Status],b.[статус заказу] [Крайній заказ: статус заказу], b.[тип створення заказу] [Крайній заказ: тип створення заказу]
/*,b.SapCounter [Крайній заказ: SapCounter]*/,b.[RealTypeZakaz],b.[дистриб'юція/зберігання] [Крайній заказ: дистриб'юція/зберігання]
,b.KolvoFirst [Крайній заказ: KolvoFirst],b.Kolvo [Крайній заказ: Kolvo]
,b.KOLVO_ZAKAZ
,b.KOLVO_POST

,case when o.[order] is null then o_add.[order] else o.[order] end [Крайній заказ (дані УТЗ): заказ]
,case when o.[Orders_short_type_id] is not null then o.[Orders_short_type_id] else b.[Orders_short_type_id] end [Крайній заказ (дані УТЗ):тип шортеджа]
,case when o.[order] is null then o_add.[demand] else o.demand end  [Крайній заказ (дані УТЗ): розрахована потреба]
,case when o.[order] is null then o_add.[pack] else o.pack end [Крайній заказ (дані УТЗ): розфасовка]
,o.[is_rotation]

,b.[Залишок на магазині на дату створення заказу на маг.]
,b.[Списання/переобліки з дати створення заказу на маг.]
,b.[Інші рухи з дати створення заказу на маг.]

,b.FILID_RC
,case when b.[SAPStatus_RC] is null then la2.SAPStatus else b.[SAPStatus_RC] end [SAPStatus_RC]
,case when b.[Remark_RC] is null then t2.Remark else b.[Remark_RC] end [Remark_RC]
,case when b.[modified_RC] is null then la2.modified else b.[modified_RC] end [modified_RC]

,b.[Залишок на РЦ на дату створення заказу на маг.]
,b.[Залишок на РЦ на дату поставки у магазин]
,b.[Залишок на РЦ на дату розрахунку]

,b.PostavshikID,b.[Contragents.FullName],b.[Contragents.InternalFilial]

,b.Created_RC [Крайній заказ на РЦ: Created]
,b.DateToPost_RC [Крайній заказ на РЦ: DateToPost]
,b.PostavshikID_external [Крайній заказ на РЦ: PostavshikID]
,k2.[Contragents.FullName] [Крайній заказ на РЦ: Contragents.FullName]
,case when dcnt.[Contragents.InternalFilial]=1 then 1 else 0 end [Магістраль на РЦ]

,#dwh_RC.maxdate [коли востаннє був залишок на РЦ]
,#dwh_RC_zakaz.maxdate_zakazRC [дата планової поставки крайнього заказу на РЦ]

,b.Kolvo_RC, b.KolvoFirst_RC
,isnull(b.KOLVO_ZAKAZ_RC,0) KOLVO_ZAKAZ_RC, isnull(b.KOLVO_POST_RC,0) KOLVO_POST_RC
,case when dg_RC2.PostID in (28091,10997327) then 'ВІ_Фора' else b.[Імпорт] end [Імпорт]

,case	when o2.orders_short_type_id is not null then 0
		when isnull(b.KOLVO_ZAKAZ_RC,0)>0 then isnull(b.KOLVO_POST_RC,0)/isnull(b.KOLVO_ZAKAZ_RC,0)
		when  isnull(b.KOLVO_POST_RC,0)=isnull(b.KOLVO_ZAKAZ_RC,0) THEN 1
		else null end [SL_RC]

,dg.PostID [Договір поставки у маг.: PostID], dg.[№ договора] [Договір поставки у маг.: № договора]
,cast(dg.[Дата начала] as date) [Договір поставки у маг.: Дата начала], dg.[Дней до поставки] [Договір поставки у маг.: Дней до поставки]
,dg.Поставщик [Договір поставки у маг.: Поставщик], dg.Частота [Договір поставки у маг.: Частота]

,dg_RC2.PostID [Договір поставки у РЦ.: PostID], dg_RC2.[№ договора] [Договір поставки у РЦ.: № договора]
,cast(dg_RC2.[Дата начала] as date) [Договір поставки у РЦ.: Дата начала]
,cast(dg_RC2.DateFinish as date) [Договір поставки у РЦ.: DateFinish]
,dg_RC2.[Дней до поставки] [Договір поставки у РЦ.: Дней до поставки]
,dg_RC2.Поставщик [Договір поставки у РЦ.: Поставщик]
,dg_RC2.Частота [Договір поставки у РЦ.: Частота]
,cast (#RC_first_shipment.DateToPost as date) [Коли була перша поставка на РЦ]
, dg.DateFinish [Договір поставки у маг.: DateFinish]
,o2.orders_short_type_id [Крайній заказ на РЦ (дані УТЗ):тип шортеджа]
,b.[дата крайньої поставки кратно дню старту договору]

into #fin
from #base1 b
left join Business_Analytic.zakaz.orders_data o on o.filid=b.filId and o.lagerid=b.LagerId and o.order_date=b.[Created] and o.income_date=b.[DateToPost]
LEFT join Business_Analytic.zakaz.orders_data_added o_add on o_add.filId=b.filId and o_add.lagerid=b.LagerId and o_add.order_date=b.[Created] and o_add.income_date=b.[DateToPost]
join Business_Analytic.dbo.Lager_cex lc on lc.id=b.LagerId 
join Business_Analytic.dbo.Dep_id d on d.Dep_id=lc.DepId_
join CB.dbo.Lager l on l.id=b.LagerId
join masterdata.dbo.dim_filials f on f.[fil.Filials.filialId]=b.filId
left join #dogov dg on dg.filId=b.filId and dg.LagerId=b.LagerId and dg.rn=1
left join #dwh_RC on #dwh_RC.FILID=b.FILID_RC and #dwh_RC.LAGERID=b.LagerId
left join #dwh_RC_zakaz on #dwh_RC_zakaz.FILID=b.FILID_RC and #dwh_RC_zakaz.LAGERID=b.LagerId
--left join #dogov_RC dg_RC on dg_RC.FilId_RC=b.FILID_RC and dg_RC.LagerId=b.LagerId and dg_RC.rn=1
left join #dogov_RC2 dg_RC2 on dg_RC2.FilidRC_dogov=b.FILID_RC and dg_RC2.LagerId=b.LagerId and dg_RC2.rn=1
left join masterdata.dbo.dim_contragents dcnt on dcnt.[Contragents.ContragentId]=b.PostavshikID_external and [Contragents.businessId]=4

left join [MasterData].[dbo].[dim_Filials] f2 on f2.[Contragents.ContragentId]=dg.PostID and dg.rn=1
left join [CB].[dbo].[LagerAssortiment] la2 on la2.LagerId=b.LagerId and la2.filId=f2.[fil.Filials.filialId]
left join [CB].[dbo].[TypeSAPStatusAssortiment] t2 on t2.[SAPStatus]=la2.[SAPStatus]
left join #RC_first_shipment on #RC_first_shipment.filid=b.FILID_RC and #RC_first_shipment.lagerid=b.LagerId and #RC_first_shipment.rn=1
left join Business_Analytic.zakaz.orders_data o2 on o2.filid=b.FILID_RC and o2.lagerid=b.LagerId and o2.order_date=b.Created_RC and o2.income_date=b.DateToPost_RC
left join MasterData.dbo.dim_Contragents k2 on k2.[Contragents.ContragentId]=b.PostavshikID_external
--declare @dat date=cast(getdate() as date)
drop table if exists #stores_RC_magistral --залишки на РЦ-постачальнику для магістралі
select es.FILID_RC, es.[Крайній заказ на РЦ: PostavshikID], es.[Крайній заказ на РЦ: Created], p.lagerid, p.filid, sum(p.kolvo) kolvo_fact
into #stores_RC_magistral 
from DataWareHouse..view_stores p
join MasterData.dbo.dim_Filials f on f.[fil.Filials.filialId]=p.FILID
join #fin es on es.LagerId=p.LagerId and es.[Крайній заказ на РЦ: Created]=p.OPERATIONDATE 
												and es.[Крайній заказ на РЦ: Created] is not null and es.[Крайній заказ на РЦ: PostavshikID]=f.[Contragents.contragentId]
												and es.[Магістраль на РЦ]=1
group by es.FILID_RC, es.[Крайній заказ на РЦ: PostavshikID],es.[Крайній заказ на РЦ: Created], p.lagerid, p.filid


drop table if exists #rotation
SELECT distinct [LagerId]      
      ,[Крайній заказ: Created]      
	  into #rotation
  FROM #fin v
  join [DBMS_Zelinskaya].[Zelinskaya].[utz].[Rotation] r on r.[new_lagerid]=v.LagerId and [Крайній заказ: Created] between r.[start_date] and r.[end_date]








drop table if exists #final
--declare @dat date='2026-04-24'
delete from [Business_Analytic].[dost].[empty_stores] where [Дата з нульовими залишками]=@dat
insert into [Business_Analytic].[dost].[empty_stores]
--declare @dat date='2026-04-24'
select 
f.[Дата з нульовими залишками]
,f.filId
,f.LagerId,f.MacroID, f.[lager typeid]
,cast (f.[Залишок на дату розрахунку, од.] as numeric(12,3)) [Залишок на дату розрахунку, од.]
,f.dateopen, f.[card_status], f.card_age
,f.[Крайня дата з залишком на магазині],f.[Cкільки днів немає залишку товару в маг.]
,cast(f.SAPStatus as nvarchar(10)) [SAPStatus]
,cast(f.Remark as nvarchar(50)) as [Remark]
,f.assort_modified--,b.created

,f.[Крайній заказ: Created],f.[Крайній заказ: DateToPost]
,f.[Заказ в путі: Created],f.[Заказ в путі: DateToPost]
,cast (f.[Заказ в путі: довідково Kolvo] as numeric(12,3)) [Заказ в путі: довідково Kolvo]

,f.[Status]
,cast(f.[Крайній заказ: статус заказу] as nvarchar(50)) [Крайній заказ: статус заказу]
,f.[Крайній заказ: тип створення заказу]
/*,f.[Крайній заказ: SapCounter]*/,f.[RealTypeZakaz],f.[Крайній заказ: дистриб'юція/зберігання]

,cast (f.[Крайній заказ: KolvoFirst] as numeric(12,3)) [Крайній заказ: KolvoFirst]
,cast (f.[Крайній заказ: Kolvo] as numeric(12,3)) [Крайній заказ: Kolvo]
,cast (f.[KOLVO_ZAKAZ] as numeric(12,3)) [KOLVO_ZAKAZ]
,cast (f.[KOLVO_POST] as numeric(12,3)) [KOLVO_POST]


,f.[Крайній заказ (дані УТЗ): заказ], f.[Крайній заказ (дані УТЗ):тип шортеджа]
,f.[Крайній заказ (дані УТЗ): розрахована потреба], f.[Крайній заказ (дані УТЗ): розфасовка]

,f.[Залишок на магазині на дату створення заказу на маг.]
,cast(f.[Списання/переобліки з дати створення заказу на маг.] as numeric(12,3)) [Списання/переобліки з дати створення заказу на маг.]
,cast(f.[Інші рухи з дати створення заказу на маг.] as numeric(12,3)) [Інші рухи з дати створення заказу на маг.]

,f.FILID_RC
,cast(f.[SAPStatus_RC] as nvarchar(5)) [SAPStatus_RC]
,cast(f.[Remark_RC] as nvarchar(50)) [Remark_RC]
,f.[modified_RC]
,cast(f.[Залишок на РЦ на дату створення заказу на маг.] as numeric(12,3)) [Залишок на РЦ на дату створення заказу на маг.]
,cast(f.[Залишок на РЦ на дату поставки у магазин] as numeric(12,3)) [Залишок на РЦ на дату поставки у магазин]
,cast(f.[Залишок на РЦ на дату розрахунку] as numeric(12,3)) [Залишок на РЦ на дату розрахунку]

,f.PostavshikID
,cast(f.[Contragents.FullName] as nvarchar(255)) [Contragents.FullName]
,f.[Contragents.InternalFilial]

,f.[Крайній заказ на РЦ: Created]
,f.[Крайній заказ на РЦ: DateToPost]
,f.[Крайній заказ на РЦ: PostavshikID]
,cast(f.[Крайній заказ на РЦ: Contragents.FullName] as nvarchar(255)) [Крайній заказ на РЦ: Contragents.FullName]
,f.[Магістраль на РЦ]

,f.[коли востаннє був залишок на РЦ]
,f.[дата планової поставки крайнього заказу на РЦ]

,cast(f.Kolvo_RC  as numeric(12,3)) [Kolvo_RC]
,cast(f.KolvoFirst_RC as numeric(12,3)) [KolvoFirst_RC]
,cast(f.KOLVO_ZAKAZ_RC as numeric(12,3)) [KOLVO_ZAKAZ_RC]
,cast(f.KOLVO_POST_RC as numeric(12,3)) [KOLVO_POST_RC]

,cast(f.[Імпорт] as nvarchar(10)) [Імпорт]
,cast(f.[SL_RC] as numeric(5,2)) [SL_RC]
,cast(case	when f.[Крайній заказ (дані УТЗ):тип шортеджа] is not null then 0
		when isnull(f.KOLVO_ZAKAZ,0)>0 then isnull(f.KOLVO_POST,0)/isnull(f.KOLVO_ZAKAZ,0) 
		when f.KOLVO_POST is not null and f.KOLVO_POST=f.KOLVO_ZAKAZ THEN 1
		else NULL end as numeric(5,2)) [SL_shop]
,f.[Договір поставки у маг.: PostID]
,cast(f.[Договір поставки у маг.: № договора] as nvarchar(10)) [Договір поставки у маг.: № договора]
,f.[Договір поставки у маг.: Дата начала], f.[Договір поставки у маг.: Дней до поставки]
,cast(f.[Договір поставки у маг.: Поставщик] as nvarchar(200)) [Договір поставки у маг.: Поставщик]
,f.[Договір поставки у маг.: Частота]

,f.[Договір поставки у РЦ.: PostID]
,cast(f.[Договір поставки у РЦ.: № договора] as nvarchar(10)) [Договір поставки у РЦ.: № договора]
,f.[Договір поставки у РЦ.: Дата начала]
,f.[Договір поставки у РЦ.: DateFinish]
,f.[Договір поставки у РЦ.: Дней до поставки]
,cast(f.[Договір поставки у РЦ.: Поставщик] as nvarchar(200)) [Договір поставки у РЦ.: Поставщик]
,f.[Договір поставки у РЦ.: Частота]


		,case when r.stock is not null then r.stock else r_all.stock end [дані БГ: залишок на РЦ на дату створення заказу в магазин]
		,case when r.available is not null then r.available else r_all.available end [дані БГ: вільний від резерву залишок на РЦ на дату створення заказу в магазин]
		
		,cast( 'Інше' as nvarchar(100)) [Причина]
	,case when #rotation.LagerId is null then 0 else 1 end [is_rotation]
	,case when r2.available is not null then r2.available else r2_all.available end [дані БГ: вільний від резерву залишок на РЦ на дату поставки в магазин]
,f.[Коли була перша поставка на РЦ]
,f.[Договір поставки у маг.: DateFinish]
,[Крайній заказ на РЦ (дані УТЗ):тип шортеджа]
,case	when pm1.filid is not null then 1
		when pm.filid is not null then 1 else 0 end [Ознака мінусової полки під час створення заказу на маг.]
,sm.kolvo_fact  [Залишок на дату створення магістр заказу на РЦ_постачальнику]
from #fin f
left join [Business_Analytic].[utz].[stockRC_rezerv] r on r.filid=f.FILID_RC and r.Date=f.[Крайній заказ: Created] and r.lagerid=f.LagerId
left join [Business_Analytic].[utz].[stockRC_rezerv] r2 on r2.filid=f.FILID_RC and r2.Date=f.[Крайній заказ: DateToPost] and r2.lagerid=f.LagerId

left join (select Date, lagerid, sum(stock) stock, sum(available) available from [Business_Analytic].[utz].[stockRC_rezerv]
			group by  Date, lagerid) r_all on r_all.Date=f.[Крайній заказ: Created] and r_all.lagerid=f.LagerId
left join (select Date, lagerid, sum(available) available from [Business_Analytic].[utz].[stockRC_rezerv]
			group by  Date, lagerid) r2_all on r2_all.Date=f.[Крайній заказ: DateToPost] and r2_all.lagerid=f.LagerId

left join [Business_Analytic].[dost].[PolkaMinus] pm on pm.filid=f.FILID and pm.[dat]=f.[Крайній заказ: Created] and pm.lagerid=f.LagerId
left join [Business_Analytic].[dost].[PolkaMinus] pm1 on pm1.filid=f.FILID and pm1.[dat]=f.[дата крайньої поставки кратно дню старту договору] and pm1.lagerid=f.LagerId
left join #stores_RC_magistral sm on sm.FILID_RC=f.FILID_RC and sm.LAGERID=f.LagerId and sm.[Крайній заказ на РЦ: PostavshikID]=f.[Крайній заказ на РЦ: PostavshikID]
			and sm.[Крайній заказ на РЦ: Created]=f.[Крайній заказ на РЦ: Created]
 
 left join #rotation on #rotation.LagerId=f.LagerId and #rotation.[Крайній заказ: Created]=f.[Крайній заказ: Created]
 
