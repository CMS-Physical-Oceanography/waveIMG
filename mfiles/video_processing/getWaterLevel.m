function [z,tz] = getWaterLevel(expID)

if strcmp(expID,'top21') || strcmp(expID,'bot21') 
    load('waterlevel_dunex.mat','z','tz')
elseif strcmp(expID,'rod13')
    load('waterlevel_rodsex.mat','z','tz')
end

end

