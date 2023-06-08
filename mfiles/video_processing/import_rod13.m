% top folder yyyymmdd and subfolder HHMM
OCMdandt = {'20130929', {'1100','1200','1300','1400'}};
% get a tally of the number of subfolders in each top folder
OCMnumfiles = 0;
for i = 1:size(OCMdandt, 1)
    OCMnumfiles = OCMnumfiles + length(OCMdandt{i,2});
end
%
tag = cell(OCMnumfiles,1);
importDir = cell(OCMnumfiles,1);
workingDir = cell(OCMnumfiles,1);
cnt = 1;
for i = 1:size(OCMdandt, 1)
    d = OCMdandt{i, 1};
    t = OCMdandt{i, 2};
    for j = 1:length(t)
        tag{cnt} = ['ROD13_' d '_' t{j}];
        % CHANGE TO YOUR IMPORT DIRECTORY
        importDir{cnt} = ['../data/' d filesep t{j}]; 
        % CHANGE TO WHEREVER YOU WANT THE DATA TO SAVE
        workingDir{cnt}= ['../data/' d]; 
        cnt = cnt + 1;
    end
end

expID = 'rod13';
for k = 1:OCMnumfiles
    [ocean,oceanSum,oceanX,oceanY,infoOCM] = rectify_vd(tag{k},workingDir{k},importDir{k},expID);
end

