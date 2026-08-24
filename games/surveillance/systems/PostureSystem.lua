-- 姿态系统入口：目前复用 FurniturePoseSystem 的实现。
-- 之后如果扩展蹲下、靠门偷听、趴下检查床底，可以在这里继续收拢接口，
-- 让场景层不再关心“家具”这个具体来源。
return require("games.surveillance.systems.FurniturePoseSystem")
